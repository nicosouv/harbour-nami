#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Face recognition using ArcFace model
Optimized for on-device processing on Sailfish OS
"""

import cv2
import numpy as np
import onnxruntime as ort
from pathlib import Path


class FaceRecognizer:
    """ArcFace-based face recognizer for face embeddings extraction"""

    def __init__(self, model_path=None):
        """
        Initialize ArcFace face recognizer

        Args:
            model_path: Path to ArcFace ONNX model
        """
        # Default model path
        if model_path is None:
            model_path = Path(__file__).parent / "models" / "arcface_mobilefacenet.onnx"

        if not Path(model_path).exists():
            raise FileNotFoundError(f"ArcFace model not found at {model_path}")

        # Initialize ONNX Runtime session
        # Use CPU provider for Sailfish OS compatibility
        providers = ['CPUExecutionProvider']

        self.session = ort.InferenceSession(str(model_path), providers=providers)

        # Get model input details
        self.input_name = self.session.get_inputs()[0].name
        self.input_shape = self.session.get_inputs()[0].shape
        self.output_name = self.session.get_outputs()[0].name

        # Expected input size (usually 112x112 for MobileFaceNet)
        self.input_size = (112, 112)
        if len(self.input_shape) == 4:
            self.input_size = (self.input_shape[2], self.input_shape[3])

        print(f"ArcFace model loaded: {model_path}")
        print(f"Input shape: {self.input_shape}")
        print(f"Expected input size: {self.input_size}")

    def preprocess(self, face_image):
        """
        Preprocess face image for model input

        Args:
            face_image: numpy array (BGR format)

        Returns:
            Preprocessed image ready for model inference
        """
        # Resize to model input size
        if face_image.shape[:2] != self.input_size:
            face_image = cv2.resize(face_image, self.input_size)

        # Convert BGR to RGB
        face_rgb = cv2.cvtColor(face_image, cv2.COLOR_BGR2RGB)

        # ArcFace preprocessing (from Hugging Face model):
        # Normalize: (pixel - 127.5) / 128.0
        face_normalized = (face_rgb.astype(np.float32) - 127.5) / 128.0

        # Check if model expects NCHW or NHWC format
        # The Hugging Face model expects (1, 112, 112, 3) - NHWC format
        if len(self.input_shape) == 4 and self.input_shape[-1] == 3:
            # NHWC format - just add batch dimension
            face_input = np.expand_dims(face_normalized, axis=0)
        else:
            # NCHW format - transpose and add batch dimension
            face_input = np.transpose(face_normalized, (2, 0, 1))
            face_input = np.expand_dims(face_input, axis=0)

        return face_input.astype(np.float32)

    def extract_embedding(self, face_image):
        """
        Extract face embedding (feature vector)

        Args:
            face_image: numpy array (BGR format)

        Returns:
            Embedding vector (normalized 512-d vector for ArcFace)
        """
        # Preprocess
        input_tensor = self.preprocess(face_image)

        # Run inference
        embedding = self.session.run([self.output_name], {self.input_name: input_tensor})[0]

        # Flatten and normalize
        embedding = embedding.flatten()
        embedding = self.normalize_embedding(embedding)

        return embedding

    @staticmethod
    def normalize_embedding(embedding):
        """Normalize embedding to unit vector (L2 normalization)"""
        norm = np.linalg.norm(embedding)
        if norm == 0:
            return embedding
        return embedding / norm

    def compute_similarity(self, embedding1, embedding2):
        """
        Compute cosine similarity between two embeddings

        Args:
            embedding1: First embedding vector
            embedding2: Second embedding vector

        Returns:
            Similarity score (0.0-1.0, higher is more similar)
        """
        # Cosine similarity (dot product of normalized vectors)
        similarity = np.dot(embedding1, embedding2)

        # Convert to [0, 1] range
        similarity = (similarity + 1.0) / 2.0

        return float(similarity)

    def compare_faces(self, face_image1, face_image2):
        """
        Compare two face images and return similarity score

        Args:
            face_image1: First face image (BGR format)
            face_image2: Second face image (BGR format)

        Returns:
            Similarity score (0.0-1.0)
        """
        emb1 = self.extract_embedding(face_image1)
        emb2 = self.extract_embedding(face_image2)

        return self.compute_similarity(emb1, emb2)

    def match_face(self, face_image, database_embeddings, threshold=0.6):
        """
        Match face against database of embeddings

        Args:
            face_image: Face image to match (BGR format)
            database_embeddings: List of (person_id, embedding) tuples
            threshold: Minimum similarity threshold for match

        Returns:
            Best match (person_id, similarity) or (None, 0.0) if no match
        """
        if not database_embeddings:
            return None, 0.0

        # Extract embedding for input face
        face_embedding = self.extract_embedding(face_image)

        # Find best match
        best_match = None
        best_similarity = 0.0

        for person_id, db_embedding in database_embeddings:
            similarity = self.compute_similarity(face_embedding, db_embedding)

            if similarity > best_similarity:
                best_similarity = similarity
                best_match = person_id

        # Check threshold
        if best_similarity < threshold:
            return None, best_similarity

        return best_match, best_similarity

    def get_embedding_size(self):
        """Get size of embedding vector"""
        return self.session.get_outputs()[0].shape[-1]


class FaceDatabase:
    """Simple in-memory face database for embeddings"""

    def __init__(self):
        """Initialize empty database"""
        self.embeddings = {}  # person_id -> list of embeddings
        self.person_names = {}  # person_id -> name
        self.next_id = 1

    def add_person(self, name, embeddings):
        """
        Add new person to database

        Args:
            name: Person name
            embeddings: List of embedding vectors for this person

        Returns:
            person_id
        """
        person_id = self.next_id
        self.next_id += 1

        self.person_names[person_id] = name
        self.embeddings[person_id] = embeddings

        return person_id

    def add_embedding(self, person_id, embedding):
        """Add embedding to existing person"""
        if person_id not in self.embeddings:
            raise ValueError(f"Person ID {person_id} not found")

        self.embeddings[person_id].append(embedding)

    def get_average_embedding(self, person_id):
        """Get average embedding for person (more robust than single embedding)"""
        if person_id not in self.embeddings:
            raise ValueError(f"Person ID {person_id} not found")

        embeddings = np.array(self.embeddings[person_id])
        avg_embedding = np.mean(embeddings, axis=0)

        # Normalize
        norm = np.linalg.norm(avg_embedding)
        if norm > 0:
            avg_embedding = avg_embedding / norm

        return avg_embedding

    def get_all_embeddings(self):
        """Get all person embeddings for matching"""
        result = []
        for person_id in self.embeddings:
            avg_emb = self.get_average_embedding(person_id)
            result.append((person_id, avg_emb))

        return result

    def get_person_name(self, person_id):
        """Get person name by ID"""
        return self.person_names.get(person_id, "Unknown")

    def remove_person(self, person_id):
        """Remove person from database"""
        if person_id in self.embeddings:
            del self.embeddings[person_id]
        if person_id in self.person_names:
            del self.person_names[person_id]

    def get_statistics(self):
        """Get database statistics"""
        total_people = len(self.embeddings)
        total_embeddings = sum(len(embs) for embs in self.embeddings.values())

        return {
            'total_people': total_people,
            'total_embeddings': total_embeddings
        }


if __name__ == "__main__":
    # Test recognizer
    print("ArcFace Face Recognizer Test")
    print("=" * 50)

    try:
        recognizer = FaceRecognizer()
        print(f"Recognizer initialized")
        print(f"Embedding size: {recognizer.get_embedding_size()}")

        # Test database
        db = FaceDatabase()
        print("\nDatabase initialized")
        print(f"Statistics: {db.get_statistics()}")

    except FileNotFoundError as e:
        print(f"Error: {e}")
        print("Please download the ArcFace model first")
