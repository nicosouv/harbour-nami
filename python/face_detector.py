#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Face detection using YuNet model
Optimized for on-device processing on Sailfish OS
"""

import cv2
import numpy as np
import os
from pathlib import Path


class FaceDetector:
    """YuNet-based face detector for real-time face detection"""

    def __init__(self, model_path=None, conf_threshold=0.6, nms_threshold=0.3):
        """
        Initialize YuNet face detector

        Args:
            model_path: Path to YuNet ONNX model
            conf_threshold: Confidence threshold for detection (0.0-1.0)
            nms_threshold: NMS threshold for overlapping boxes
        """
        self.conf_threshold = conf_threshold
        self.nms_threshold = nms_threshold

        # Default model path
        if model_path is None:
            model_path = Path(__file__).parent / "models" / "face_detection_yunet_2023mar.onnx"

        if not os.path.exists(model_path):
            raise FileNotFoundError(f"YuNet model not found at {model_path}")

        # Initialize YuNet detector
        self.detector = cv2.FaceDetectorYN.create(
            str(model_path),
            "",
            (320, 320),  # Default input size
            conf_threshold,
            nms_threshold
        )

        self.input_size = (320, 320)

    def set_input_size(self, width, height):
        """Set input image size for detection"""
        self.input_size = (width, height)
        self.detector.setInputSize(self.input_size)

    def detect(self, image):
        """
        Detect faces in image

        Args:
            image: numpy array (BGR format)

        Returns:
            List of face detections, each containing:
            - bbox: [x, y, w, h]
            - confidence: float
            - landmarks: 5 facial landmarks (2 eyes, nose, 2 mouth corners)
        """
        if image is None or image.size == 0:
            return []

        height, width = image.shape[:2]

        # Adjust detector input size to match image
        if (width, height) != self.input_size:
            self.set_input_size(width, height)

        # Detect faces
        _, faces = self.detector.detect(image)

        if faces is None:
            return []

        # Parse detections
        detections = []
        for face in faces:
            # YuNet output format: [x, y, w, h, x_re, y_re, x_le, y_le, x_nt, y_nt, x_rcm, y_rcm, x_lcm, y_lcm, conf]
            # First 4: bounding box
            # Next 10: 5 landmarks (right eye, left eye, nose tip, right corner mouth, left corner mouth)
            # Last: confidence score

            bbox = face[:4].astype(int)
            landmarks = face[4:14].reshape(5, 2).astype(int)
            confidence = float(face[14])

            detection = {
                'bbox': bbox.tolist(),  # [x, y, w, h]
                'confidence': confidence,
                'landmarks': landmarks.tolist(),  # [[x, y], ...]
                'x': int(bbox[0]),
                'y': int(bbox[1]),
                'width': int(bbox[2]),
                'height': int(bbox[3])
            }

            detections.append(detection)

        return detections

    def detect_from_file(self, image_path):
        """
        Detect faces from image file

        Args:
            image_path: Path to image file

        Returns:
            List of face detections
        """
        image = cv2.imread(str(image_path))
        if image is None:
            raise ValueError(f"Could not read image from {image_path}")

        return self.detect(image)

    def visualize_detections(self, image, detections):
        """
        Draw bounding boxes and landmarks on image

        Args:
            image: numpy array (BGR format)
            detections: List of face detections

        Returns:
            Image with visualizations drawn
        """
        vis_image = image.copy()

        for det in detections:
            # Draw bounding box
            x, y, w, h = det['bbox']
            cv2.rectangle(vis_image, (x, y), (x + w, y + h), (0, 255, 0), 2)

            # Draw confidence
            conf_text = f"{det['confidence']:.2f}"
            cv2.putText(vis_image, conf_text, (x, y - 10),
                       cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 255, 0), 2)

            # Draw landmarks
            for landmark in det['landmarks']:
                cv2.circle(vis_image, tuple(landmark), 2, (0, 0, 255), -1)

        return vis_image

    def crop_face(self, image, detection, padding=0.2):
        """
        Crop face region from image with padding

        Args:
            image: numpy array (BGR format)
            detection: Single face detection dict
            padding: Padding ratio around face (0.0-1.0)

        Returns:
            Cropped face image
        """
        x, y, w, h = detection['bbox']

        # Add padding
        pad_w = int(w * padding)
        pad_h = int(h * padding)

        x1 = max(0, x - pad_w)
        y1 = max(0, y - pad_h)
        x2 = min(image.shape[1], x + w + pad_w)
        y2 = min(image.shape[0], y + h + pad_h)

        face_crop = image[y1:y2, x1:x2]

        return face_crop

    def align_face(self, image, detection, output_size=(112, 112)):
        """
        Align face using landmarks (for better recognition)

        Args:
            image: numpy array (BGR format)
            detection: Single face detection dict
            output_size: Size of output aligned face

        Returns:
            Aligned face image
        """
        landmarks = np.array(detection['landmarks'], dtype=np.float32)

        # Use eye landmarks for alignment
        left_eye = landmarks[0]  # Right eye in image (left eye of person)
        right_eye = landmarks[1]  # Left eye in image (right eye of person)

        # Calculate angle
        dy = right_eye[1] - left_eye[1]
        dx = right_eye[0] - left_eye[0]
        angle = np.degrees(np.arctan2(dy, dx))

        # Get center point between eyes
        eye_center = ((left_eye[0] + right_eye[0]) / 2,
                     (left_eye[1] + right_eye[1]) / 2)

        # Get rotation matrix
        M = cv2.getRotationMatrix2D(eye_center, angle, 1.0)

        # Rotate image
        aligned = cv2.warpAffine(image, M, (image.shape[1], image.shape[0]))

        # Crop and resize to output size
        face_crop = self.crop_face(aligned, detection, padding=0.3)
        face_resized = cv2.resize(face_crop, output_size)

        return face_resized


if __name__ == "__main__":
    # Test detector
    print("YuNet Face Detector Test")
    print("=" * 50)

    # Initialize detector
    detector = FaceDetector()
    print(f"Detector initialized")
    print(f"Confidence threshold: {detector.conf_threshold}")
    print(f"NMS threshold: {detector.nms_threshold}")
