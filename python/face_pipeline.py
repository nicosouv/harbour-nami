#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Face recognition pipeline for Nami
Coordinates detection, recognition, and database operations
Optimized for on-device processing on Sailfish OS
"""

import cv2
import numpy as np
from pathlib import Path
from typing import List, Dict, Tuple, Optional
import time

from face_detector import FaceDetector
from face_recognizer import FaceRecognizer
from database import DatabaseManager


class FaceRecognitionPipeline:
    """Complete face recognition pipeline"""

    def __init__(self, db_path=None, detector_conf=0.6, recognition_threshold=0.65):
        """
        Initialize pipeline

        Args:
            db_path: Path to database file
            detector_conf: Face detection confidence threshold
            recognition_threshold: Face recognition similarity threshold
        """
        self.detector = FaceDetector(conf_threshold=detector_conf)
        self.recognizer = FaceRecognizer()
        self.db = DatabaseManager(db_path=db_path)

        self.recognition_threshold = recognition_threshold

        print("Face Recognition Pipeline initialized")
        print(f"Detection confidence: {detector_conf}")
        print(f"Recognition threshold: {recognition_threshold}")

    def process_photo(self, photo_path, auto_recognize=True):
        """
        Process single photo: detect faces, extract embeddings, optionally recognize

        Args:
            photo_path: Path to photo file
            auto_recognize: Automatically try to recognize faces

        Returns:
            Dict with processing results
        """
        start_time = time.time()

        # Load image
        image = cv2.imread(str(photo_path))
        if image is None:
            return {'error': f'Could not load image: {photo_path}'}

        height, width = image.shape[:2]
        file_size = Path(photo_path).stat().st_size

        # Add photo to database
        photo = self.db.get_photo_by_path(str(photo_path))
        if photo is None:
            photo_id = self.db.add_photo(str(photo_path), width, height, file_size)
        else:
            photo_id = photo['id']

        # Detect faces
        detections = self.detector.detect(image)

        results = {
            'photo_id': photo_id,
            'photo_path': str(photo_path),
            'detections': len(detections),
            'faces': []
        }

        # Process each detected face
        for det in detections:
            # Crop and align face
            face_aligned = self.detector.align_face(image, det)

            # Extract embedding
            embedding = self.recognizer.extract_embedding(face_aligned)

            # Save to database
            face_id = self.db.add_face(
                photo_id=photo_id,
                bbox=det['bbox'],
                landmarks=det['landmarks'],
                embedding=embedding,
                confidence=det['confidence']
            )

            face_result = {
                'face_id': face_id,
                'bbox': det['bbox'],
                'confidence': det['confidence'],
                'person_id': None,
                'person_name': None,
                'similarity': 0.0
            }

            # Try to recognize face
            if auto_recognize:
                person_id, similarity = self.recognize_face(face_id)
                if person_id is not None:
                    face_result['person_id'] = person_id
                    face_result['person_name'] = self.db.get_person(person_id)['name']
                    face_result['similarity'] = similarity

                    # Map face to person
                    self.db.map_face_to_person(face_id, person_id, similarity, verified=False)

            results['faces'].append(face_result)

        # Mark photo as analyzed
        self.db.mark_photo_analyzed(photo_id)

        # Performance metrics
        elapsed = time.time() - start_time
        results['processing_time'] = elapsed

        return results

    def process_batch(self, photo_paths, progress_callback=None):
        """
        Process batch of photos

        Args:
            photo_paths: List of photo paths
            progress_callback: Optional callback(current, total, photo_path)

        Returns:
            List of processing results
        """
        results = []
        total = len(photo_paths)

        for i, photo_path in enumerate(photo_paths):
            if progress_callback:
                progress_callback(i + 1, total, photo_path)

            result = self.process_photo(photo_path)
            results.append(result)

        return results

    def recognize_face(self, face_id):
        """
        Try to recognize face by matching against known people

        Args:
            face_id: Face ID to recognize

        Returns:
            (person_id, similarity) or (None, 0.0) if no match
        """
        # Get face embedding
        face_embedding = self.db.get_face_embedding(face_id)
        if face_embedding is None:
            return None, 0.0

        # Get all people with their average embeddings
        all_people = self.db.get_all_people()
        if not all_people:
            return None, 0.0

        best_match = None
        best_similarity = 0.0

        for person in all_people:
            person_id = person['id']

            # Get average embedding for this person
            person_faces = self.db.get_faces_for_person(person_id)
            if not person_faces:
                continue

            # Compute average embedding
            embeddings = []
            for face in person_faces:
                emb = self.db.get_face_embedding(face['id'])
                if emb is not None:
                    embeddings.append(emb)

            if not embeddings:
                continue

            avg_embedding = np.mean(embeddings, axis=0)
            avg_embedding = self.recognizer.normalize_embedding(avg_embedding)

            # Compute similarity
            similarity = self.recognizer.compute_similarity(face_embedding, avg_embedding)

            if similarity > best_similarity:
                best_similarity = similarity
                best_match = person_id

        # Check threshold
        if best_similarity < self.recognition_threshold:
            return None, best_similarity

        return best_match, best_similarity

    def create_person_from_face(self, face_id, name, contact_id=None):
        """
        Create new person from face

        Args:
            face_id: Face ID to use
            name: Person name
            contact_id: Optional contact ID

        Returns:
            person_id
        """
        # Create person
        person_id = self.db.add_person(name=name, contact_id=contact_id)

        # Map face to person
        self.db.map_face_to_person(face_id, person_id, verified=True)

        return person_id

    def assign_face_to_person(self, face_id, person_id, verified=True):
        """
        Manually assign face to person

        Args:
            face_id: Face ID
            person_id: Person ID
            verified: Mark as verified by user

        Returns:
            bool: Success
        """
        # Get face embedding
        face_embedding = self.db.get_face_embedding(face_id)
        if face_embedding is None:
            return False

        # Get person average embedding for similarity
        person_faces = self.db.get_faces_for_person(person_id)
        if person_faces:
            embeddings = [self.db.get_face_embedding(f['id']) for f in person_faces]
            embeddings = [e for e in embeddings if e is not None]

            if embeddings:
                avg_embedding = np.mean(embeddings, axis=0)
                avg_embedding = self.recognizer.normalize_embedding(avg_embedding)
                similarity = self.recognizer.compute_similarity(face_embedding, avg_embedding)
            else:
                similarity = 1.0
        else:
            similarity = 1.0  # First face for this person

        # Map face to person
        self.db.map_face_to_person(face_id, person_id, similarity, verified)

        return True

    def group_unknown_faces(self, similarity_threshold=0.7):
        """
        Group unmapped faces by similarity (clustering)

        Args:
            similarity_threshold: Threshold for grouping

        Returns:
            List of face groups (list of face_ids)
        """
        # Get unmapped faces
        unmapped_faces = self.db.get_unmapped_faces()
        if not unmapped_faces:
            return []

        # Extract embeddings
        face_ids = []
        embeddings = []
        for face in unmapped_faces:
            emb = self.db.get_face_embedding(face['id'])
            if emb is not None:
                face_ids.append(face['id'])
                embeddings.append(emb)

        if not embeddings:
            return []

        # Simple clustering by similarity
        groups = []
        assigned = set()

        for i, face_id in enumerate(face_ids):
            if face_id in assigned:
                continue

            # Start new group
            group = [face_id]
            assigned.add(face_id)

            # Find similar faces
            for j, other_id in enumerate(face_ids):
                if i == j or other_id in assigned:
                    continue

                similarity = self.recognizer.compute_similarity(embeddings[i], embeddings[j])

                if similarity >= similarity_threshold:
                    group.append(other_id)
                    assigned.add(other_id)

            groups.append(group)

        return groups

    def get_person_summary(self, person_id):
        """
        Get summary information for person

        Args:
            person_id: Person ID

        Returns:
            Dict with person information
        """
        person = self.db.get_person(person_id)
        if person is None:
            return None

        photo_count = self.db.get_person_photo_count(person_id)
        faces = self.db.get_faces_for_person(person_id)

        return {
            'person_id': person_id,
            'name': person['name'],
            'contact_id': person['contact_id'],
            'photo_count': photo_count,
            'face_count': len(faces),
            'created_at': person['created_at'],
            'updated_at': person['updated_at']
        }

    def get_all_people_summaries(self):
        """Get summaries for all people"""
        people = self.db.get_all_people()
        summaries = []

        for person in people:
            summary = self.get_person_summary(person['id'])
            if summary:
                summaries.append(summary)

        return summaries

    def scan_gallery(self, gallery_path, progress_callback=None):
        """
        Scan entire gallery directory

        Args:
            gallery_path: Path to gallery directory
            progress_callback: Optional callback(current, total, photo_path)

        Returns:
            Processing summary
        """
        gallery_path = Path(gallery_path)

        # Find all image files
        image_extensions = {'.jpg', '.jpeg', '.png', '.bmp', '.webp'}
        photo_paths = []

        for ext in image_extensions:
            photo_paths.extend(gallery_path.rglob(f'*{ext}'))
            photo_paths.extend(gallery_path.rglob(f'*{ext.upper()}'))

        print(f"Found {len(photo_paths)} photos in gallery")

        # Process batch
        results = self.process_batch(photo_paths, progress_callback)

        # Compute summary
        total_faces = sum(r.get('detections', 0) for r in results)
        total_time = sum(r.get('processing_time', 0) for r in results)
        avg_time = total_time / len(results) if results else 0

        return {
            'total_photos': len(results),
            'total_faces': total_faces,
            'total_time': total_time,
            'avg_time_per_photo': avg_time,
            'results': results
        }

    def export_data(self, export_path):
        """
        Export all data for GDPR compliance

        Args:
            export_path: Path to export file

        Returns:
            bool: Success
        """
        import json

        # Get all data
        people = self.db.get_all_people()
        stats = self.db.get_statistics()

        export_data = {
            'export_date': time.strftime('%Y-%m-%d %H:%M:%S'),
            'statistics': stats,
            'people': []
        }

        for person in people:
            person_data = {
                'id': person['id'],
                'name': person['name'],
                'contact_id': person['contact_id'],
                'created_at': person['created_at'],
                'photos': []
            }

            photos = self.db.get_photos_for_person(person['id'])
            for photo in photos:
                person_data['photos'].append({
                    'path': photo['path'],
                    'timestamp': photo['timestamp']
                })

            export_data['people'].append(person_data)

        # Write to file
        with open(export_path, 'w') as f:
            json.dump(export_data, f, indent=2)

        return True

    def clear_all_data(self):
        """Clear all face recognition data (GDPR right to be forgotten)"""
        self.db.clear_all_data()
        self.db.vacuum()

    def get_statistics(self):
        """Get pipeline statistics"""
        return self.db.get_statistics()

    def close(self):
        """Close pipeline and cleanup resources"""
        self.db.close()


if __name__ == "__main__":
    # Test pipeline
    print("Face Recognition Pipeline Test")
    print("=" * 50)

    pipeline = FaceRecognitionPipeline()
    print("Pipeline initialized")

    stats = pipeline.get_statistics()
    print(f"\nStatistics:")
    for key, value in stats.items():
        print(f"  {key}: {value}")

    pipeline.close()
