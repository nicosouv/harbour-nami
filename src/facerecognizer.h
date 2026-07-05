#ifndef FACERECOGNIZER_H
#define FACERECOGNIZER_H

#include <QObject>
#include <QString>
#include <QVector>
#include <opencv2/opencv.hpp>
#include <opencv2/objdetect.hpp>
#include "facedetector.h"

/**
 * @brief Face embedding (128-d vector for SFace)
 */
using FaceEmbedding = std::vector<float>;

/**
 * @brief Match result
 */
struct FaceMatch {
    int personId;
    float similarity;  // 0.0 - 1.0
};

/**
 * @brief SFace-based face recognition using OpenCV FaceRecognizerSF
 *
 * Uses the official OpenCV Zoo SFace model, designed to pair with YuNet:
 * alignCrop() consumes YuNet landmarks directly and feature() applies the
 * exact preprocessing the model was trained with.
 *
 * Extracts 128-dimensional embeddings, compared with cosine similarity.
 * The official cosine decision threshold is 0.363, i.e. ~0.68 on the
 * rescaled [0,1] similarity used across the app.
 */
class FaceRecognizer : public QObject
{
    Q_OBJECT

public:
    explicit FaceRecognizer(QObject *parent = nullptr);
    ~FaceRecognizer();

    /**
     * @brief Load the SFace ONNX model
     * @param modelPath Path to face_recognition_sface_2021dec.onnx
     * @return true if loaded successfully
     */
    bool loadModel(const QString &modelPath);

    /**
     * @brief Extract face embedding from a detected face
     * @param image Full image (BGR)
     * @param detection Face detection with normalized bbox and landmarks
     * @return 128-d embedding vector (L2-normalized), empty on failure
     */
    FaceEmbedding extractEmbedding(const cv::Mat &image, const FaceDetection &detection);

    /**
     * @brief Compute cosine similarity between two embeddings
     * @param emb1 First embedding
     * @param emb2 Second embedding
     * @return Similarity score (0.0 - 1.0, higher = more similar)
     */
    static float computeSimilarity(const FaceEmbedding &emb1, const FaceEmbedding &emb2);

    /**
     * @brief Normalize embedding to unit vector (L2 normalization)
     */
    static FaceEmbedding normalizeEmbedding(const FaceEmbedding &embedding);

    /**
     * @brief Check if model is loaded
     */
    bool isLoaded() const { return m_modelLoaded; }

    /**
     * @brief Get expected input size
     */
    QSize inputSize() const { return QSize(112, 112); }

signals:
    void error(const QString &message);

private:
    cv::Ptr<cv::FaceRecognizerSF> m_recognizer;
    bool m_modelLoaded;

    // Helper: Build the 1x15 YuNet-format face row (pixel coordinates)
    // expected by FaceRecognizerSF::alignCrop
    static cv::Mat detectionToFaceRow(const cv::Mat &image, const FaceDetection &detection);
};

#endif // FACERECOGNIZER_H
