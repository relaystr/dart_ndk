import 'package:logger/logger.dart' as lib_logger;

mixin class Logger {
  static const _defaultLogLevel = lib_logger.Level.debug;

  static final _myPrinter = lib_logger.PrettyPrinter(
    methodCount: 0,
    printEmojis: false,
    printTime: false,
    //noBoxingByDefault: true,
  );

  static lib_logger.Logger log = lib_logger.Logger(
    printer: _myPrinter,
    level: _defaultLogLevel,
  );

  static setLogLevel(lib_logger.Level level) {
    log = lib_logger.Logger(
      printer: _myPrinter,
      level: level,
    );
  }
}
