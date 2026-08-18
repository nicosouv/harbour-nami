#ifndef FACEEMBEDDING_H
#define FACEEMBEDDING_H

#include <vector>

/**
 * @brief Face embedding (128-d vector for SFace)
 *
 * Kept in a header of its own so the storage layer can talk about
 * embeddings without pulling in OpenCV: FaceDatabase only ever moves these
 * vectors in and out of SQLite, and dragging the whole vision stack behind
 * it would make the database impossible to test on its own.
 */
using FaceEmbedding = std::vector<float>;

#endif // FACEEMBEDDING_H
