#ifndef LOGGING_H
#define LOGGING_H

#include <QLoggingCategory>

// Verbose pipeline logging, disabled by default. Enable with:
//   QT_LOGGING_RULES="nami.pipeline.debug=true" harbour-nami
Q_DECLARE_LOGGING_CATEGORY(lcNami)

#endif // LOGGING_H
