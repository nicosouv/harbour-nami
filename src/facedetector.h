#ifndef FACEDETECTOR_H
#define FACEDETECTOR_H

#include <QObject>
#include <QImage>
#include <QRectF>
#include <QVector>
#include <QString>
#include <opencv2/opencv.hpp>
#include <opencv2/dnn.hpp>

/**
 * @brief Face detection result
 */
struct FaceDetection {
    QRectF bbox;              // Bounding box (normalized 0-1)
    float confidence;         // Detection confidence (0-1)
    QVector<QPointF> landmarks; // 5 facial landmarks (eyes, nose, mouth corners)
};

/**
 * @brief YuNet-based face detector using OpenCV DNN
 *
 * Fast on-device face detection optimized for mobile.
 * Target: 30+ FPS on Sailfish OS devices.
 */
class FaceDetector : public QObject
{
    Q_OBJECT

public:
    explicit FaceDetector(QObject *parent = nullptr);
    ~FaceDetector();

    /**
     * @brief Load the YuNet ONNX model
     * @param modelPath Path to face_detection_yunet_2023mar.onnx
     * @return true if loaded successfully
     */
    bool loadModel(const QString &modelPath);

    /**
     * @brief Detect faces in an image
     * @param image Input image (QImage or cv::Mat)
     * @param confidenceThreshold Minimum confidence (default: 0.6)
     * @return Vector of detected faces
     */
    QVector<FaceDetection> detect(const QImage &image, float confidenceThreshold = 0.6f);
    QVector<FaceDetection> detect(const cv::Mat &image, float confidenceThreshold = 0.6f);

    /**
     * @brief Check if model is loaded
     */
    bool isLoaded() const { return m_modelLoaded; }

    /**
     * @brief Get input size for the model
     */
    QSize inputSize() const { return m_inputSize; }

signals:
    void error(const QString &message);

private:
    cv::dnn::Net m_net;
    bool m_modelLoaded;
    QSize m_inputSize;

    // Helper: Convert QImage to cv::Mat
    cv::Mat qImageToCvMat(const QImage &image);

    // Helper: Preprocess image for YuNet
    cv::Mat preprocessImage(const cv::Mat &image);

    // Helper: Post-process YuNet output
    QVector<FaceDetection> postprocessDetections(const cv::Mat &output,
                                                  const QSize &imageSize,
                                                  float confidenceThreshold);
};

#endif // FACEDETECTOR_H
