#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Download ML models for Nami face recognition
- YuNet face detection model
- ArcFace MobileFaceNet recognition model
"""

import os
import urllib.request
import hashlib
from pathlib import Path


def download_file(url, dest_path, expected_sha256=None):
    """
    Download file with progress and verification

    Args:
        url: URL to download from
        dest_path: Destination file path
        expected_sha256: Optional SHA256 checksum for verification
    """
    print(f"Downloading {os.path.basename(dest_path)}...")
    print(f"URL: {url}")

    # Create directory if needed
    os.makedirs(os.path.dirname(dest_path), exist_ok=True)

    # Download with progress
    def progress_hook(count, block_size, total_size):
        percent = int(count * block_size * 100 / total_size)
        print(f"\rProgress: {percent}% ({count * block_size}/{total_size} bytes)", end='')

    urllib.request.urlretrieve(url, dest_path, progress_hook)
    print()  # New line after progress

    # Verify checksum if provided
    if expected_sha256:
        print("Verifying checksum...")
        sha256_hash = hashlib.sha256()
        with open(dest_path, "rb") as f:
            for byte_block in iter(lambda: f.read(4096), b""):
                sha256_hash.update(byte_block)

        actual_sha256 = sha256_hash.hexdigest()

        if actual_sha256 == expected_sha256:
            print("✓ Checksum verified")
        else:
            print(f"✗ Checksum mismatch!")
            print(f"  Expected: {expected_sha256}")
            print(f"  Actual:   {actual_sha256}")
            os.remove(dest_path)
            raise ValueError("Checksum verification failed")

    file_size = os.path.getsize(dest_path)
    print(f"✓ Downloaded: {file_size / 1024 / 1024:.2f} MB\n")


def main():
    """Download all required models"""

    # Get models directory
    models_dir = Path(__file__).parent / "models"
    models_dir.mkdir(exist_ok=True)

    print("=" * 60)
    print("Nami Face Recognition - Model Download")
    print("=" * 60)
    print()

    # YuNet face detection model
    # Source: OpenCV Zoo - https://github.com/opencv/opencv_zoo
    yunet_url = "https://github.com/opencv/opencv_zoo/raw/main/models/face_detection_yunet/face_detection_yunet_2023mar.onnx"
    yunet_path = models_dir / "face_detection_yunet_2023mar.onnx"
    yunet_sha256 = "e1f3e892af5f4dd8f0bde2b9a05c3c6d7b4c05b8b06b73b8c5f7e8c3e6c0f9a4"  # Example, update with real hash

    if yunet_path.exists():
        print(f"✓ YuNet model already exists: {yunet_path}")
    else:
        try:
            download_file(yunet_url, str(yunet_path))
            print(f"✓ YuNet model downloaded successfully")
        except Exception as e:
            print(f"✗ Failed to download YuNet model: {e}")

    print()

    # ArcFace MobileFaceNet model
    # Note: This is a placeholder URL - you'll need to host the model or use an alternative source
    # Option 1: Use InsightFace pre-trained models
    # Option 2: Convert and host your own
    # Option 3: Use ONNX Model Zoo

    arcface_url = "https://github.com/onnx/models/raw/main/vision/body_analysis/arcface/model/arcfaceresnet100-8.onnx"
    arcface_path = models_dir / "arcface_mobilefacenet.onnx"

    print("ArcFace Model:")
    print("─" * 60)
    print("⚠️  ArcFace model requires manual download or conversion")
    print()
    print("Options:")
    print()
    print("1. Download from InsightFace:")
    print("   https://github.com/deepinsight/insightface/tree/master/model_zoo")
    print()
    print("2. Use ONNX Model Zoo ArcFace (larger, more accurate):")
    print("   https://github.com/onnx/models/tree/main/vision/body_analysis/arcface")
    print()
    print("3. Convert PyTorch/TensorFlow model to ONNX:")
    print("   Use MobileFaceNet for better mobile performance")
    print()
    print(f"Place model file at: {arcface_path}")
    print()

    if arcface_path.exists():
        print(f"✓ ArcFace model found: {arcface_path}")
    else:
        print(f"✗ ArcFace model not found")
        print(f"  Please download and place at: {arcface_path}")

    print()
    print("=" * 60)

    # Summary
    print("\nModel Status:")
    print(f"  YuNet (Detection):     {'✓ Ready' if yunet_path.exists() else '✗ Missing'}")
    print(f"  ArcFace (Recognition): {'✓ Ready' if arcface_path.exists() else '✗ Missing'}")
    print()

    if yunet_path.exists() and arcface_path.exists():
        print("✓ All models ready!")
        return 0
    else:
        print("⚠️  Some models are missing. Please download them manually.")
        return 1


if __name__ == "__main__":
    exit(main())
