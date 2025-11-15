#include "facedetector.h"
#include <QDebug>

FaceDetector::FaceDetector(QObject *parent)
    : QObject(parent)
    , m_modelLoaded(false)
    , m_inputSize(320, 320)  // Default YuNet input size
{
}

FaceDetector::~FaceDetector()
{
}

bool FaceDetector::loadModel(const QString &modelPath)
{
    try {
        qDebug() << "Loading YuNet face detection model from:" << modelPath;

        // Load ONNX model using OpenCV DNN
        m_net = cv::dnn::readNetFromONNX(modelPath.toStdString());

        if (m_net.empty()) {
            emit error("Failed to load YuNet model: empty network");
            return false;
        }

        // Set backend and target (CPU for Sailfish OS)
        m_net.setPreferableBackend(cv::dnn::DNN_BACKEND_OPENCV);
        m_net.setPreferableTarget(cv::dnn::DNN_TARGET_CPU);

        m_modelLoaded = true;
        qDebug() << "YuNet model loaded successfully";
        qDebug() << "Input size:" << m_inputSize.width() << "x" << m_inputSize.height();

        return true;
    }
    catch (const cv::Exception &e) {
        QString errorMsg = QString("OpenCV exception loading model: %1").arg(e.what());
        qWarning() << errorMsg;
        emit error(errorMsg);
        return false;
    }
}

QVector<FaceDetection> FaceDetector::detect(const QImage &image, float confidenceThreshold)
{
    qDebug() << "QImage detection requested - size:" << image.width() << "x" << image.height();
    cv::Mat mat = qImageToCvMat(image);
    qDebug() << "Converted to cv::Mat - size:" << mat.cols << "x" << mat.rows;
    return detect(mat, confidenceThreshold);
}

QVector<FaceDetection> FaceDetector::detect(const cv::Mat &image, float confidenceThreshold)
{
    if (!m_modelLoaded) {
        emit error("Model not loaded");
        return QVector<FaceDetection>();
    }

    if (image.empty()) {
        emit error("Empty input image");
        return QVector<FaceDetection>();
    }

    qDebug() << "=== Face Detection Start ===";
    qDebug() << "Input image size:" << image.cols << "x" << image.rows << "channels:" << image.channels();
    qDebug() << "Confidence threshold:" << confidenceThreshold;

    try {
        // Preprocess image
        qDebug() << "Preprocessing image...";
        cv::Mat blob = preprocessImage(image);
        qDebug() << "Blob created - size:" << blob.size[2] << "x" << blob.size[3] << "channels:" << blob.size[1];

        // Set input
        qDebug() << "Setting network input...";
        m_net.setInput(blob);

        // Forward pass
        qDebug() << "Running forward pass...";
        cv::Mat output = m_net.forward();
        qDebug() << "Network output shape: rows=" << output.rows << "cols=" << output.cols << "dims=" << output.dims;

        // Post-process detections
        qDebug() << "Post-processing detections...";
        QVector<FaceDetection> detections = postprocessDetections(
            output,
            QSize(image.cols, image.rows),
            confidenceThreshold
        );

        qDebug() << "=== Detection Complete: Found" << detections.size() << "faces (threshold=" << confidenceThreshold << ") ===";

        return detections;
    }
    catch (const cv::Exception &e) {
        QString errorMsg = QString("OpenCV exception during detection: %1").arg(e.what());
        qWarning() << errorMsg;
        emit error(errorMsg);
        return QVector<FaceDetection>();
    }
}

cv::Mat FaceDetector::qImageToCvMat(const QImage &image)
{
    // Convert QImage to cv::Mat
    QImage rgb = image.convertToFormat(QImage::Format_RGB888);
    cv::Mat mat(rgb.height(), rgb.width(), CV_8UC3,
                const_cast<uchar*>(rgb.bits()), rgb.bytesPerLine());

    // Clone to ensure data persistence
    return mat.clone();
}

cv::Mat FaceDetector::preprocessImage(const cv::Mat &image)
{
    // YuNet expects RGB image, 320x320, normalized [0, 1]
    cv::Mat resized;
    cv::resize(image, resized, cv::Size(m_inputSize.width(), m_inputSize.height()));

    // Convert BGR to RGB if needed
    cv::Mat rgb;
    if (image.channels() == 3) {
        cv::cvtColor(resized, rgb, cv::COLOR_BGR2RGB);
    } else {
        rgb = resized;
    }

    // Create blob: [1, 3, H, W], normalized [0, 1]
    cv::Mat blob = cv::dnn::blobFromImage(rgb, 1.0/255.0,
                                          cv::Size(m_inputSize.width(), m_inputSize.height()),
                                          cv::Scalar(0, 0, 0), false, false);

    return blob;
}

QVector<FaceDetection> FaceDetector::postprocessDetections(const cv::Mat &output,
                                                            const QSize &imageSize,
                                                            float confidenceThreshold)
{
    QVector<FaceDetection> detections;

    // YuNet output format: [num_detections, 15]
    // [x, y, w, h, x_re, y_re, x_le, y_le, x_nt, y_nt, x_rcm, y_rcm, x_lcm, y_lcm, score]
    // where: re = right eye, le = left eye, nt = nose tip, rcm = right corner mouth, lcm = left corner mouth

    qDebug() << "Post-processing" << output.rows << "potential detections";

    int rejectedCount = 0;
    float maxScore = -1.0f;

    for (int i = 0; i < output.rows; i++) {
        const float *row = output.ptr<float>(i);

        float score = row[14];

        if (score > maxScore) {
            maxScore = score;
        }

        if (i < 5) {  // Log first 5 detections
            qDebug() << "  Detection" << i << "- score:" << score
                     << "bbox: [" << row[0] << row[1] << row[2] << row[3] << "]";
        }

        if (score >= confidenceThreshold) {
            FaceDetection detection;

            // Bounding box (normalize to 0-1)
            float x = row[0] / imageSize.width();
            float y = row[1] / imageSize.height();
            float w = row[2] / imageSize.width();
            float h = row[3] / imageSize.height();

            detection.bbox = QRectF(x, y, w, h);
            detection.confidence = score;

            // 5 landmarks (normalize to 0-1)
            for (int j = 0; j < 5; j++) {
                float lx = row[4 + j*2] / imageSize.width();
                float ly = row[5 + j*2] / imageSize.height();
                detection.landmarks.append(QPointF(lx, ly));
            }

            detections.append(detection);
            qDebug() << "  ✓ Accepted detection" << i << "with score" << score;
        } else {
            rejectedCount++;
        }
    }

    qDebug() << "Rejected" << rejectedCount << "detections below threshold" << confidenceThreshold;
    qDebug() << "Max score found:" << maxScore;

    return detections;
}
