#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
SQLite database manager for Nami face recognition
Handles photos, faces, people, and mappings
"""

import sqlite3
import json
import numpy as np
from pathlib import Path
from datetime import datetime
from typing import List, Tuple, Optional


class DatabaseManager:
    """SQLite database manager for face recognition data"""

    def __init__(self, db_path=None):
        """
        Initialize database connection

        Args:
            db_path: Path to SQLite database file
        """
        if db_path is None:
            # Default path: ~/.local/share/harbour-nami/database.db
            data_dir = Path.home() / ".local" / "share" / "harbour-nami"
            data_dir.mkdir(parents=True, exist_ok=True)
            db_path = data_dir / "database.db"

        self.db_path = str(db_path)
        self.conn = None
        self.connect()
        self.create_tables()

    def connect(self):
        """Connect to database"""
        self.conn = sqlite3.connect(self.db_path)
        self.conn.row_factory = sqlite3.Row  # Access columns by name
        return self.conn

    def close(self):
        """Close database connection"""
        if self.conn:
            self.conn.close()
            self.conn = None

    def create_tables(self):
        """Create database tables if they don't exist"""
        cursor = self.conn.cursor()

        # Photos table
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS photos (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                path TEXT UNIQUE NOT NULL,
                timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
                analyzed BOOLEAN DEFAULT 0,
                width INTEGER,
                height INTEGER,
                file_size INTEGER
            )
        """)

        # Faces table (detected faces in photos)
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS faces (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                photo_id INTEGER NOT NULL,
                bbox_x INTEGER NOT NULL,
                bbox_y INTEGER NOT NULL,
                bbox_width INTEGER NOT NULL,
                bbox_height INTEGER NOT NULL,
                landmarks TEXT,
                embedding BLOB NOT NULL,
                confidence REAL NOT NULL,
                detected_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (photo_id) REFERENCES photos (id) ON DELETE CASCADE
            )
        """)

        # People table (recognized persons)
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS people (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT,
                contact_id TEXT,
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                notes TEXT
            )
        """)

        # Face-Person mapping table
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS face_mapping (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                face_id INTEGER NOT NULL,
                person_id INTEGER NOT NULL,
                verified BOOLEAN DEFAULT 0,
                similarity REAL,
                mapped_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (face_id) REFERENCES faces (id) ON DELETE CASCADE,
                FOREIGN KEY (person_id) REFERENCES people (id) ON DELETE CASCADE,
                UNIQUE(face_id, person_id)
            )
        """)

        # Settings table (app configuration)
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS settings (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL,
                updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
            )
        """)

        # Create indexes for performance
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_photos_analyzed ON photos(analyzed)")
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_photos_timestamp ON photos(timestamp)")
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_faces_photo ON faces(photo_id)")
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_faces_confidence ON faces(confidence)")
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_mapping_face ON face_mapping(face_id)")
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_mapping_person ON face_mapping(person_id)")

        self.conn.commit()

    # ========== Photo Operations ==========

    def add_photo(self, path, width=None, height=None, file_size=None):
        """Add photo to database"""
        cursor = self.conn.cursor()
        cursor.execute("""
            INSERT OR IGNORE INTO photos (path, width, height, file_size)
            VALUES (?, ?, ?, ?)
        """, (path, width, height, file_size))
        self.conn.commit()
        return cursor.lastrowid

    def get_photo(self, photo_id):
        """Get photo by ID"""
        cursor = self.conn.cursor()
        cursor.execute("SELECT * FROM photos WHERE id = ?", (photo_id,))
        return cursor.fetchone()

    def get_photo_by_path(self, path):
        """Get photo by path"""
        cursor = self.conn.cursor()
        cursor.execute("SELECT * FROM photos WHERE path = ?", (path,))
        return cursor.fetchone()

    def mark_photo_analyzed(self, photo_id):
        """Mark photo as analyzed"""
        cursor = self.conn.cursor()
        cursor.execute("UPDATE photos SET analyzed = 1 WHERE id = ?", (photo_id,))
        self.conn.commit()

    def get_unanalyzed_photos(self, limit=None):
        """Get photos that haven't been analyzed yet"""
        cursor = self.conn.cursor()
        query = "SELECT * FROM photos WHERE analyzed = 0 ORDER BY timestamp DESC"
        if limit:
            query += f" LIMIT {limit}"
        cursor.execute(query)
        return cursor.fetchall()

    def get_all_photos(self):
        """Get all photos"""
        cursor = self.conn.cursor()
        cursor.execute("SELECT * FROM photos ORDER BY timestamp DESC")
        return cursor.fetchall()

    # ========== Face Operations ==========

    def add_face(self, photo_id, bbox, landmarks, embedding, confidence):
        """
        Add detected face to database

        Args:
            photo_id: Photo ID
            bbox: [x, y, width, height]
            landmarks: List of facial landmarks
            embedding: Numpy array embedding vector
            confidence: Detection confidence

        Returns:
            face_id
        """
        cursor = self.conn.cursor()

        # Serialize embedding as bytes
        embedding_bytes = embedding.tobytes()

        # Serialize landmarks as JSON
        landmarks_json = json.dumps(landmarks)

        cursor.execute("""
            INSERT INTO faces (photo_id, bbox_x, bbox_y, bbox_width, bbox_height,
                             landmarks, embedding, confidence)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """, (photo_id, bbox[0], bbox[1], bbox[2], bbox[3],
              landmarks_json, embedding_bytes, confidence))

        self.conn.commit()
        return cursor.lastrowid

    def get_face(self, face_id):
        """Get face by ID"""
        cursor = self.conn.cursor()
        cursor.execute("SELECT * FROM faces WHERE id = ?", (face_id,))
        return cursor.fetchone()

    def get_faces_by_photo(self, photo_id):
        """Get all faces in a photo"""
        cursor = self.conn.cursor()
        cursor.execute("SELECT * FROM faces WHERE photo_id = ?", (photo_id,))
        return cursor.fetchall()

    def get_face_embedding(self, face_id, embedding_size=512):
        """Get face embedding as numpy array"""
        face = self.get_face(face_id)
        if face is None:
            return None

        embedding_bytes = face['embedding']
        embedding = np.frombuffer(embedding_bytes, dtype=np.float32)

        # Ensure correct size
        if len(embedding) != embedding_size:
            print(f"Warning: Expected embedding size {embedding_size}, got {len(embedding)}")

        return embedding

    def get_all_faces(self):
        """Get all faces"""
        cursor = self.conn.cursor()
        cursor.execute("SELECT * FROM faces ORDER BY detected_at DESC")
        return cursor.fetchall()

    def get_unmapped_faces(self):
        """Get faces that haven't been mapped to a person yet"""
        cursor = self.conn.cursor()
        cursor.execute("""
            SELECT f.* FROM faces f
            LEFT JOIN face_mapping fm ON f.id = fm.face_id
            WHERE fm.face_id IS NULL
            ORDER BY f.detected_at DESC
        """)
        return cursor.fetchall()

    # ========== Person Operations ==========

    def add_person(self, name=None, contact_id=None, notes=None):
        """Add new person"""
        cursor = self.conn.cursor()
        cursor.execute("""
            INSERT INTO people (name, contact_id, notes)
            VALUES (?, ?, ?)
        """, (name, contact_id, notes))
        self.conn.commit()
        return cursor.lastrowid

    def get_person(self, person_id):
        """Get person by ID"""
        cursor = self.conn.cursor()
        cursor.execute("SELECT * FROM people WHERE id = ?", (person_id,))
        return cursor.fetchone()

    def update_person(self, person_id, name=None, contact_id=None, notes=None):
        """Update person information"""
        cursor = self.conn.cursor()

        updates = []
        params = []

        if name is not None:
            updates.append("name = ?")
            params.append(name)
        if contact_id is not None:
            updates.append("contact_id = ?")
            params.append(contact_id)
        if notes is not None:
            updates.append("notes = ?")
            params.append(notes)

        if not updates:
            return

        updates.append("updated_at = CURRENT_TIMESTAMP")
        params.append(person_id)

        query = f"UPDATE people SET {', '.join(updates)} WHERE id = ?"
        cursor.execute(query, params)
        self.conn.commit()

    def delete_person(self, person_id):
        """Delete person (and all face mappings)"""
        cursor = self.conn.cursor()
        cursor.execute("DELETE FROM people WHERE id = ?", (person_id,))
        self.conn.commit()

    def get_all_people(self):
        """Get all people"""
        cursor = self.conn.cursor()
        cursor.execute("SELECT * FROM people ORDER BY name")
        return cursor.fetchall()

    # ========== Face-Person Mapping Operations ==========

    def map_face_to_person(self, face_id, person_id, similarity=None, verified=False):
        """Map face to person"""
        cursor = self.conn.cursor()
        cursor.execute("""
            INSERT OR REPLACE INTO face_mapping (face_id, person_id, similarity, verified)
            VALUES (?, ?, ?, ?)
        """, (face_id, person_id, similarity, verified))
        self.conn.commit()
        return cursor.lastrowid

    def get_person_for_face(self, face_id):
        """Get person mapped to face"""
        cursor = self.conn.cursor()
        cursor.execute("""
            SELECT p.* FROM people p
            JOIN face_mapping fm ON p.id = fm.person_id
            WHERE fm.face_id = ?
        """, (face_id,))
        return cursor.fetchone()

    def get_faces_for_person(self, person_id):
        """Get all faces for a person"""
        cursor = self.conn.cursor()
        cursor.execute("""
            SELECT f.* FROM faces f
            JOIN face_mapping fm ON f.id = fm.face_id
            WHERE fm.person_id = ?
            ORDER BY f.detected_at DESC
        """, (person_id,))
        return cursor.fetchall()

    def get_photos_for_person(self, person_id):
        """Get all photos containing a person"""
        cursor = self.conn.cursor()
        cursor.execute("""
            SELECT DISTINCT p.* FROM photos p
            JOIN faces f ON p.id = f.photo_id
            JOIN face_mapping fm ON f.id = fm.face_id
            WHERE fm.person_id = ?
            ORDER BY p.timestamp DESC
        """, (person_id,))
        return cursor.fetchall()

    def verify_mapping(self, face_id, person_id):
        """Mark face-person mapping as verified by user"""
        cursor = self.conn.cursor()
        cursor.execute("""
            UPDATE face_mapping SET verified = 1
            WHERE face_id = ? AND person_id = ?
        """, (face_id, person_id))
        self.conn.commit()

    def unmap_face(self, face_id):
        """Remove face-person mapping"""
        cursor = self.conn.cursor()
        cursor.execute("DELETE FROM face_mapping WHERE face_id = ?", (face_id,))
        self.conn.commit()

    # ========== Statistics ==========

    def get_statistics(self):
        """Get database statistics"""
        cursor = self.conn.cursor()

        # Total photos
        cursor.execute("SELECT COUNT(*) FROM photos")
        total_photos = cursor.fetchone()[0]

        # Analyzed photos
        cursor.execute("SELECT COUNT(*) FROM photos WHERE analyzed = 1")
        analyzed_photos = cursor.fetchone()[0]

        # Total faces
        cursor.execute("SELECT COUNT(*) FROM faces")
        total_faces = cursor.fetchone()[0]

        # Total people
        cursor.execute("SELECT COUNT(*) FROM people")
        total_people = cursor.fetchone()[0]

        # Mapped faces
        cursor.execute("SELECT COUNT(*) FROM face_mapping")
        mapped_faces = cursor.fetchone()[0]

        # Verified mappings
        cursor.execute("SELECT COUNT(*) FROM face_mapping WHERE verified = 1")
        verified_mappings = cursor.fetchone()[0]

        return {
            'total_photos': total_photos,
            'analyzed_photos': analyzed_photos,
            'total_faces': total_faces,
            'total_people': total_people,
            'mapped_faces': mapped_faces,
            'verified_mappings': verified_mappings,
            'unmapped_faces': total_faces - mapped_faces
        }

    def get_person_photo_count(self, person_id):
        """Get number of photos for a person"""
        cursor = self.conn.cursor()
        cursor.execute("""
            SELECT COUNT(DISTINCT f.photo_id) FROM faces f
            JOIN face_mapping fm ON f.id = fm.face_id
            WHERE fm.person_id = ?
        """, (person_id,))
        return cursor.fetchone()[0]

    # ========== Settings ==========

    def set_setting(self, key, value):
        """Set application setting"""
        cursor = self.conn.cursor()
        cursor.execute("""
            INSERT OR REPLACE INTO settings (key, value, updated_at)
            VALUES (?, ?, CURRENT_TIMESTAMP)
        """, (key, str(value)))
        self.conn.commit()

    def get_setting(self, key, default=None):
        """Get application setting"""
        cursor = self.conn.cursor()
        cursor.execute("SELECT value FROM settings WHERE key = ?", (key,))
        row = cursor.fetchone()
        return row['value'] if row else default

    # ========== Cleanup ==========

    def clear_all_data(self):
        """Clear all face recognition data (GDPR right to be forgotten)"""
        cursor = self.conn.cursor()

        # Delete in correct order due to foreign keys
        cursor.execute("DELETE FROM face_mapping")
        cursor.execute("DELETE FROM faces")
        cursor.execute("DELETE FROM people")
        cursor.execute("DELETE FROM photos")

        self.conn.commit()

    def vacuum(self):
        """Vacuum database to reclaim space"""
        self.conn.execute("VACUUM")


if __name__ == "__main__":
    # Test database
    print("Database Manager Test")
    print("=" * 50)

    db = DatabaseManager()
    print(f"Database initialized: {db.db_path}")

    stats = db.get_statistics()
    print(f"\nStatistics:")
    for key, value in stats.items():
        print(f"  {key}: {value}")

    db.close()
