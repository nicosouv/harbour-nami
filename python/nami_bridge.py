#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
PyOtherSide bridge for Nami
Exposes face recognition functionality to QML
"""

import pyotherside
import sys
from pathlib import Path

# Add current directory to path
sys.path.insert(0, str(Path(__file__).parent))

from face_pipeline import FaceRecognitionPipeline
from model_downloader import ModelDownloader


class NamiBridge:
    """Bridge between Python backend and QML frontend"""

    def __init__(self):
        """Initialize bridge"""
        self.pipeline = None
        self.processing = False
        self.downloader = ModelDownloader()

        pyotherside.send('bridge-ready')

    def check_models(self):
        """
        Check if ML models are available

        Returns:
            dict: Model availability status
        """
        try:
            status = self.downloader.check_models_available()
            info = self.downloader.get_model_info()

            return {
                'success': True,
                'models_ready': status['all_ready'],
                'yunet_available': status['yunet'],
                'arcface_available': status['arcface'],
                'model_info': info
            }

        except Exception as e:
            error_msg = f"Failed to check models: {str(e)}"
            return {
                'success': False,
                'error': error_msg,
                'models_ready': False
            }

    def download_models(self):
        """
        Download missing ML models

        Returns:
            dict: Download status
        """
        try:
            pyotherside.send('download-started')

            def progress_callback(model_name, current, total, percentage):
                pyotherside.send('download-progress', {
                    'model': model_name,
                    'current': current,
                    'total': total,
                    'percentage': percentage
                })

            results = self.downloader.download_all_models(progress_callback)

            if results['all_success']:
                pyotherside.send('download-completed', results)
            else:
                pyotherside.send('download-failed', results)

            return {
                'success': results['all_success'],
                'results': results
            }

        except Exception as e:
            error_msg = f"Failed to download models: {str(e)}"
            pyotherside.send('error', error_msg)
            return {
                'success': False,
                'error': error_msg
            }

    def initialize(self, db_path=None, detector_conf=0.6, recognition_threshold=0.65):
        """
        Initialize face recognition pipeline

        Args:
            db_path: Optional database path
            detector_conf: Detection confidence threshold
            recognition_threshold: Recognition similarity threshold

        Returns:
            dict: Initialization status
        """
        try:
            # Check if models are available first
            model_status = self.check_models()
            if not model_status['models_ready']:
                return {
                    'success': False,
                    'error': 'ML models not available',
                    'models_missing': True,
                    'model_status': model_status
                }

            self.pipeline = FaceRecognitionPipeline(
                db_path=db_path,
                detector_conf=detector_conf,
                recognition_threshold=recognition_threshold
            )

            stats = self.pipeline.get_statistics()

            pyotherside.send('initialized', stats)

            return {
                'success': True,
                'statistics': stats
            }

        except Exception as e:
            error_msg = f"Failed to initialize pipeline: {str(e)}"
            pyotherside.send('error', error_msg)
            return {
                'success': False,
                'error': error_msg
            }

    def process_photo(self, photo_path, auto_recognize=True):
        """
        Process single photo

        Args:
            photo_path: Path to photo
            auto_recognize: Auto-recognize faces

        Returns:
            dict: Processing results
        """
        if self.pipeline is None:
            return {'error': 'Pipeline not initialized'}

        try:
            result = self.pipeline.process_photo(photo_path, auto_recognize)

            pyotherside.send('photo-processed', result)

            return result

        except Exception as e:
            error_msg = f"Failed to process photo: {str(e)}"
            pyotherside.send('error', error_msg)
            return {'error': error_msg}

    def scan_gallery(self, gallery_path):
        """
        Scan entire gallery

        Args:
            gallery_path: Path to gallery directory

        Returns:
            dict: Scan summary
        """
        if self.pipeline is None:
            return {'error': 'Pipeline not initialized'}

        if self.processing:
            return {'error': 'Already processing'}

        try:
            self.processing = True
            pyotherside.send('scan-started', gallery_path)

            def progress_callback(current, total, photo_path):
                pyotherside.send('scan-progress', {
                    'current': current,
                    'total': total,
                    'photo_path': photo_path,
                    'percentage': int((current / total) * 100)
                })

            result = self.pipeline.scan_gallery(gallery_path, progress_callback)

            self.processing = False
            pyotherside.send('scan-completed', result)

            return result

        except Exception as e:
            self.processing = False
            error_msg = f"Failed to scan gallery: {str(e)}"
            pyotherside.send('error', error_msg)
            return {'error': error_msg}

    def get_all_people(self):
        """
        Get all people with summaries

        Returns:
            list: People summaries
        """
        if self.pipeline is None:
            return {'error': 'Pipeline not initialized'}

        try:
            summaries = self.pipeline.get_all_people_summaries()
            return summaries

        except Exception as e:
            error_msg = f"Failed to get people: {str(e)}"
            pyotherside.send('error', error_msg)
            return {'error': error_msg}

    def get_person_photos(self, person_id):
        """
        Get photos for person

        Args:
            person_id: Person ID

        Returns:
            list: Photo records
        """
        if self.pipeline is None:
            return {'error': 'Pipeline not initialized'}

        try:
            photos = self.pipeline.db.get_photos_for_person(person_id)

            # Convert to list of dicts
            result = []
            for photo in photos:
                result.append({
                    'id': photo['id'],
                    'path': photo['path'],
                    'timestamp': photo['timestamp'],
                    'width': photo['width'],
                    'height': photo['height']
                })

            return result

        except Exception as e:
            error_msg = f"Failed to get photos: {str(e)}"
            pyotherside.send('error', error_msg)
            return {'error': error_msg}

    def create_person(self, face_id, name, contact_id=None):
        """
        Create person from face

        Args:
            face_id: Face ID
            name: Person name
            contact_id: Optional contact ID

        Returns:
            dict: Created person info
        """
        if self.pipeline is None:
            return {'error': 'Pipeline not initialized'}

        try:
            person_id = self.pipeline.create_person_from_face(face_id, name, contact_id)

            person = self.pipeline.db.get_person(person_id)

            result = {
                'person_id': person_id,
                'name': person['name'],
                'contact_id': person['contact_id']
            }

            pyotherside.send('person-created', result)

            return result

        except Exception as e:
            error_msg = f"Failed to create person: {str(e)}"
            pyotherside.send('error', error_msg)
            return {'error': error_msg}

    def update_person(self, person_id, name=None, contact_id=None):
        """
        Update person information

        Args:
            person_id: Person ID
            name: New name (optional)
            contact_id: New contact ID (optional)

        Returns:
            dict: Update status
        """
        if self.pipeline is None:
            return {'error': 'Pipeline not initialized'}

        try:
            self.pipeline.db.update_person(person_id, name, contact_id)

            person = self.pipeline.db.get_person(person_id)

            result = {
                'success': True,
                'person_id': person_id,
                'name': person['name'],
                'contact_id': person['contact_id']
            }

            pyotherside.send('person-updated', result)

            return result

        except Exception as e:
            error_msg = f"Failed to update person: {str(e)}"
            pyotherside.send('error', error_msg)
            return {'error': error_msg}

    def delete_person(self, person_id):
        """
        Delete person

        Args:
            person_id: Person ID

        Returns:
            dict: Delete status
        """
        if self.pipeline is None:
            return {'error': 'Pipeline not initialized'}

        try:
            self.pipeline.db.delete_person(person_id)

            pyotherside.send('person-deleted', {'person_id': person_id})

            return {'success': True}

        except Exception as e:
            error_msg = f"Failed to delete person: {str(e)}"
            pyotherside.send('error', error_msg)
            return {'error': error_msg}

    def assign_face_to_person(self, face_id, person_id):
        """
        Manually assign face to person

        Args:
            face_id: Face ID
            person_id: Person ID

        Returns:
            dict: Assignment status
        """
        if self.pipeline is None:
            return {'error': 'Pipeline not initialized'}

        try:
            success = self.pipeline.assign_face_to_person(face_id, person_id, verified=True)

            if success:
                pyotherside.send('face-assigned', {
                    'face_id': face_id,
                    'person_id': person_id
                })

            return {'success': success}

        except Exception as e:
            error_msg = f"Failed to assign face: {str(e)}"
            pyotherside.send('error', error_msg)
            return {'error': error_msg}

    def get_unmapped_faces(self):
        """
        Get faces that haven't been mapped to people

        Returns:
            list: Unmapped face records
        """
        if self.pipeline is None:
            return {'error': 'Pipeline not initialized'}

        try:
            faces = self.pipeline.db.get_unmapped_faces()

            result = []
            for face in faces:
                # Get photo info
                photo = self.pipeline.db.get_photo(face['photo_id'])

                result.append({
                    'face_id': face['id'],
                    'photo_id': face['photo_id'],
                    'photo_path': photo['path'],
                    'bbox': [face['bbox_x'], face['bbox_y'],
                            face['bbox_width'], face['bbox_height']],
                    'confidence': face['confidence']
                })

            return result

        except Exception as e:
            error_msg = f"Failed to get unmapped faces: {str(e)}"
            pyotherside.send('error', error_msg)
            return {'error': error_msg}

    def group_unknown_faces(self, similarity_threshold=0.7):
        """
        Group unmapped faces by similarity

        Args:
            similarity_threshold: Similarity threshold for grouping

        Returns:
            list: Face groups
        """
        if self.pipeline is None:
            return {'error': 'Pipeline not initialized'}

        try:
            groups = self.pipeline.group_unknown_faces(similarity_threshold)

            pyotherside.send('faces-grouped', {
                'groups': len(groups),
                'total_faces': sum(len(g) for g in groups)
            })

            return groups

        except Exception as e:
            error_msg = f"Failed to group faces: {str(e)}"
            pyotherside.send('error', error_msg)
            return {'error': error_msg}

    def export_data(self, export_path):
        """
        Export all data (GDPR)

        Args:
            export_path: Export file path

        Returns:
            dict: Export status
        """
        if self.pipeline is None:
            return {'error': 'Pipeline not initialized'}

        try:
            success = self.pipeline.export_data(export_path)

            if success:
                pyotherside.send('data-exported', {'path': export_path})

            return {'success': success, 'path': export_path}

        except Exception as e:
            error_msg = f"Failed to export data: {str(e)}"
            pyotherside.send('error', error_msg)
            return {'error': error_msg}

    def clear_all_data(self):
        """
        Clear all data (GDPR right to be forgotten)

        Returns:
            dict: Clear status
        """
        if self.pipeline is None:
            return {'error': 'Pipeline not initialized'}

        try:
            self.pipeline.clear_all_data()

            pyotherside.send('data-cleared')

            return {'success': True}

        except Exception as e:
            error_msg = f"Failed to clear data: {str(e)}"
            pyotherside.send('error', error_msg)
            return {'error': error_msg}

    def get_statistics(self):
        """
        Get pipeline statistics

        Returns:
            dict: Statistics
        """
        if self.pipeline is None:
            return {'error': 'Pipeline not initialized'}

        try:
            stats = self.pipeline.get_statistics()
            return stats

        except Exception as e:
            error_msg = f"Failed to get statistics: {str(e)}"
            pyotherside.send('error', error_msg)
            return {'error': error_msg}


# Create global bridge instance
bridge = NamiBridge()


# Expose functions to QML
def check_models():
    return bridge.check_models()

def download_models():
    return bridge.download_models()

def initialize(db_path=None, detector_conf=0.6, recognition_threshold=0.65):
    return bridge.initialize(db_path, detector_conf, recognition_threshold)


def process_photo(photo_path, auto_recognize=True):
    return bridge.process_photo(photo_path, auto_recognize)


def scan_gallery(gallery_path):
    return bridge.scan_gallery(gallery_path)


def get_all_people():
    return bridge.get_all_people()


def get_person_photos(person_id):
    return bridge.get_person_photos(person_id)


def create_person(face_id, name, contact_id=None):
    return bridge.create_person(face_id, name, contact_id)


def update_person(person_id, name=None, contact_id=None):
    return bridge.update_person(person_id, name, contact_id)


def delete_person(person_id):
    return bridge.delete_person(person_id)


def assign_face_to_person(face_id, person_id):
    return bridge.assign_face_to_person(face_id, person_id)


def get_unmapped_faces():
    return bridge.get_unmapped_faces()


def group_unknown_faces(similarity_threshold=0.7):
    return bridge.group_unknown_faces(similarity_threshold)


def export_data(export_path):
    return bridge.export_data(export_path)


def clear_all_data():
    return bridge.clear_all_data()


def get_statistics():
    return bridge.get_statistics()
