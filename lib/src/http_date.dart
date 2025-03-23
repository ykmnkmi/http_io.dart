// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of 'http.dart';

/// Utility functions for working with dates with HTTP specific date
/// formats.
base class HttpDate {
  // From RFC-2616 section "3.3.1 Full Date",
  // http://tools.ietf.org/html/rfc2616#section-3.3.1
  //
  // HTTP-date    = rfc1123-date | rfc850-date | asctime-date
  // rfc1123-date = wkday "," SP date1 SP time SP "GMT"
  // rfc850-date  = weekday "," SP date2 SP time SP "GMT"
  // asctime-date = wkday SP date3 SP time SP 4DIGIT
  // date1        = 2DIGIT SP month SP 4DIGIT
  //                ; day month year (e.g., 02 Jun 1982)
  // date2        = 2DIGIT "-" month "-" 2DIGIT
  //                ; day-month-year (e.g., 02-Jun-82)
  // date3        = month SP ( 2DIGIT | ( SP 1DIGIT ))
  //                ; month day (e.g., Jun  2)
  // time         = 2DIGIT ":" 2DIGIT ":" 2DIGIT
  //                ; 00:00:00 - 23:59:59
  // wkday        = "Mon" | "Tue" | "Wed"
  //              | "Thu" | "Fri" | "Sat" | "Sun"
  // weekday      = "Monday" | "Tuesday" | "Wednesday"
  //              | "Thursday" | "Friday" | "Saturday" | "Sunday"
  // month        = "Jan" | "Feb" | "Mar" | "Apr"
  //              | "May" | "Jun" | "Jul" | "Aug"
  //              | "Sep" | "Oct" | "Nov" | "Dec"

  /// Format a date according to
  /// [RFC-1123](http://tools.ietf.org/html/rfc1123 "RFC-1123"),
  /// e.g. `Thu, 1 Jan 1970 00:00:00 GMT`.
  static String format(DateTime date) {
    const List<String> wkday = <String>[
      'Mon',
      'Tue',
      'Wed',
      'Thu',
      'Fri',
      'Sat',
      'Sun',
    ];

    const List<String> month = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    DateTime utcDate = date.toUtc();

    StringBuffer buffer =
        StringBuffer()
          ..write(wkday[utcDate.weekday - 1])
          ..write(', ')
          ..write(utcDate.day <= 9 ? '0' : '')
          ..write(utcDate.day.toString())
          ..write(' ')
          ..write(month[utcDate.month - 1])
          ..write(' ')
          ..write(utcDate.year.toString())
          ..write(utcDate.hour <= 9 ? ' 0' : ' ')
          ..write(utcDate.hour.toString())
          ..write(utcDate.minute <= 9 ? ':0' : ':')
          ..write(utcDate.minute.toString())
          ..write(utcDate.second <= 9 ? ':0' : ':')
          ..write(utcDate.second.toString())
          ..write(' GMT');

    return buffer.toString();
  }

  /// Parse a date string in either of the formats
  /// [RFC-1123](http://tools.ietf.org/html/rfc1123 "RFC-1123"),
  /// [RFC-850](http://tools.ietf.org/html/rfc850 "RFC-850") or
  /// ANSI C's asctime() format. These formats are listed here.
  ///
  ///     Thu, 1 Jan 1970 00:00:00 GMT
  ///     Thursday, 1-Jan-1970 00:00:00 GMT
  ///     Thu Jan  1 00:00:00 1970
  ///
  /// For more information see [RFC-2616 section
  /// 3.1.1](http://tools.ietf.org/html/rfc2616#section-3.3.1
  /// "RFC-2616 section 3.1.1").
  static DateTime parse(String date) {
    const int sp = 32;

    const List<String> weekDaysShort = <String>[
      'Mon',
      'Tue',
      'Wed',
      'Thu',
      'Fri',
      'Sat',
      'Sun',
    ];

    const List<String> weekdays = <String>[
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];

    const List<String> months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    int formatRfc1123 = 0;
    int formatRfc850 = 1;
    int formatAsctime = 2;

    int index = 0;
    String temp;

    void expect(String string) {
      if (date.length - index < string.length) {
        throw HttpException('Invalid HTTP date $date');
      }

      String temp = date.substring(index, index + string.length);

      if (temp != string) {
        throw HttpException('Invalid HTTP date $date');
      }

      index += string.length;
    }

    int expectWeekday() {
      int weekday;

      // The formatting of the weekday signals the format of the date string.
      int position = date.indexOf(',', index);

      if (position == -1) {
        int pos = date.indexOf(' ', index);

        if (pos == -1) {
          throw HttpException('Invalid HTTP date $date');
        }

        temp = date.substring(index, pos);
        index = pos + 1;
        weekday = weekDaysShort.indexOf(temp);

        if (weekday != -1) {
          return formatAsctime;
        }
      } else {
        temp = date.substring(index, position);
        index = position + 1;
        weekday = weekDaysShort.indexOf(temp);

        if (weekday != -1) {
          return formatRfc1123;
        }

        weekday = weekdays.indexOf(temp);

        if (weekday != -1) {
          return formatRfc850;
        }
      }

      throw HttpException('Invalid HTTP date $date');
    }

    int expectMonth(String separator) {
      int position = date.indexOf(separator, index);

      if (position - index != 3) {
        throw HttpException('Invalid HTTP date $date');
      }

      temp = date.substring(index, position);
      index = position + 1;

      int month = months.indexOf(temp);

      if (month != -1) {
        return month;
      }

      throw HttpException('Invalid HTTP date $date');
    }

    int expectNum(String separator) {
      int position;

      if (separator.isNotEmpty) {
        position = date.indexOf(separator, index);
      } else {
        position = date.length;
      }

      String temp = date.substring(index, position);
      index = position + separator.length;

      try {
        int value = int.parse(temp);
        return value;
      } on FormatException {
        throw HttpException('Invalid HTTP date $date');
      }
    }

    void expectEnd() {
      if (index != date.length) {
        throw HttpException('Invalid HTTP date $date');
      }
    }

    int format = expectWeekday();
    int year;
    int month;
    int day;
    int hours;
    int minutes;
    int seconds;

    if (format == formatAsctime) {
      month = expectMonth(' ');

      if (date.codeUnitAt(index) == sp) {
        index++;
      }

      day = expectNum(' ');
      hours = expectNum(':');
      minutes = expectNum(':');
      seconds = expectNum(' ');
      year = expectNum('');
    } else {
      expect(' ');
      day = expectNum(format == formatRfc1123 ? ' ' : '-');
      month = expectMonth(format == formatRfc1123 ? ' ' : '-');
      year = expectNum(' ');
      hours = expectNum(':');
      minutes = expectNum(':');
      seconds = expectNum(' ');
      expect('GMT');
    }

    expectEnd();
    return DateTime.utc(year, month + 1, day, hours, minutes, seconds, 0);
  }

  // Parse a cookie date string.
  static DateTime _parseCookieDate(String date) {
    const List<String> monthsLowerCase = <String>[
      'jan',
      'feb',
      'mar',
      'apr',
      'may',
      'jun',
      'jul',
      'aug',
      'sep',
      'oct',
      'nov',
      'dec',
    ];

    int position = 0;

    Never error() {
      throw HttpException('Invalid cookie date $date');
    }

    bool isEnd() {
      return position == date.length;
    }

    bool isDelimiter(String s) {
      int char = s.codeUnitAt(0);

      if (char == 0x09) {
        return true;
      }

      if (char >= 0x20 && char <= 0x2F) {
        return true;
      }

      if (char >= 0x3B && char <= 0x40) {
        return true;
      }

      if (char >= 0x5B && char <= 0x60) {
        return true;
      }

      if (char >= 0x7B && char <= 0x7E) {
        return true;
      }

      return false;
    }

    bool isNonDelimiter(String s) {
      int char = s.codeUnitAt(0);

      if (char >= 0x00 && char <= 0x08) {
        return true;
      }

      if (char >= 0x0A && char <= 0x1F) {
        return true;
      }

      if (char >= 0x30 && char <= 0x39) {
        return true; // Digit
      }

      if (char == 0x3A) {
        return true; // ':'
      }

      if (char >= 0x41 && char <= 0x5A) {
        return true; // Alpha
      }

      if (char >= 0x61 && char <= 0x7A) {
        return true; // Alpha
      }

      if (char >= 0x7F && char <= 0xFF) {
        return true; // Alpha
      }

      return false;
    }

    bool isDigit(String s) {
      int char = s.codeUnitAt(0);

      if (char > 0x2F && char < 0x3A) {
        return true;
      }

      return false;
    }

    int getMonth(String month) {
      if (month.length < 3) {
        return -1;
      }

      return monthsLowerCase.indexOf(month.substring(0, 3));
    }

    int toInt(String s) {
      int index = 0;

      for (; index < s.length && isDigit(s[index]); index++) {}

      return int.parse(s.substring(0, index));
    }

    List<String> tokens = <String>[];

    while (!isEnd()) {
      while (!isEnd() && isDelimiter(date[position])) {
        position++;
      }

      int start = position;

      while (!isEnd() && isNonDelimiter(date[position])) {
        position++;
      }

      tokens.add(date.substring(start, position).toLowerCase());

      while (!isEnd() && isDelimiter(date[position])) {
        position++;
      }
    }

    String? timeString;
    String? dayOfMonthStr;
    String? monthString;
    String? yearString;

    for (int i = 0; i < tokens.length; i++) {
      String token = tokens[i];

      if (token.isEmpty) {
        continue;
      }

      if (timeString == null &&
          token.length >= 5 &&
          isDigit(token[0]) &&
          (token[1] == ':' || (isDigit(token[1]) && token[2] == ':'))) {
        timeString = token;
      } else if (dayOfMonthStr == null && isDigit(token[0])) {
        dayOfMonthStr = token;
      } else if (monthString == null && getMonth(token) >= 0) {
        monthString = token;
      } else if (yearString == null &&
          token.length >= 2 &&
          isDigit(token[0]) &&
          isDigit(token[1])) {
        yearString = token;
      }
    }

    if (timeString == null ||
        dayOfMonthStr == null ||
        monthString == null ||
        yearString == null) {
      error();
    }

    int year = toInt(yearString);

    if (year >= 70 && year <= 99) {
      year += 1900;
    } else if (year >= 0 && year <= 69) {
      year += 2000;
    }

    if (year < 1601) {
      error();
    }

    int dayOfMonth = toInt(dayOfMonthStr);

    if (dayOfMonth < 1 || dayOfMonth > 31) {
      error();
    }

    int month = getMonth(monthString) + 1;

    List<String> timeList = timeString.split(':');

    if (timeList.length != 3) {
      error();
    }

    int hour = toInt(timeList[0]);
    int minute = toInt(timeList[1]);
    int second = toInt(timeList[2]);

    if (hour > 23) {
      error();
    }

    if (minute > 59) {
      error();
    }

    if (second > 59) {
      error();
    }

    return DateTime.utc(year, month, dayOfMonth, hour, minute, second, 0);
  }
}
