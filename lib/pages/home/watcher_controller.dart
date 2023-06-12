import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'package:disable_battery_optimization/disable_battery_optimization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_archive/flutter_archive.dart';
import 'package:flutter_notification_listener/flutter_notification_listener.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pitm/utils.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart';
import '../../constants.dart';
import '../../models/record.dart';

class WatcherController extends GetxController {
  static WatcherController get to => Get.find();
  final records = <Record>[].obs;

  /// This records2 is used for the HomeScreen, it will pop
  /// and push record when out of limit.
  final records2 = <Record>[].obs;
  final isListening = false.obs;

  static showNB({VoidCallback? onConfirm, required String title}) {
    return Get.defaultDialog(
      titlePadding: const EdgeInsets.only(top: 20),
      titleStyle: const TextStyle(fontSize: 22),
      contentPadding: const EdgeInsets.symmetric(horizontal: 25, vertical: 8),
      title: title,
      content: Text(
        "Note Bene! This app requires notification listener permission and battery optimization turned off to work.".tr,
        style: const TextStyle(fontSize: 16),
      ),
      confirm: TextButton(
        child: const Text(
          "Ok",
          style: TextStyle(fontSize: 20),
        ),
        onPressed: () {
          if (onConfirm != null) {
            onConfirm();
          }

          Get.back();
        },
      ),
    );
  }

  addRecord(Record record) async {
    records.add(record);
    if (records2.length > 2000) {
      records2.insert(0, record);
      records2.removeLast();
    } else {
      records2.add(record);
    }

    // await recordsBox.add(record);
  }

  Future<void> clearRecords() async {
    records.value = [];
    records2.value = [];
    // await recordsBox.clear();
  }

  @override
  void onInit() async {
    super.onInit();

    bool hasPermission = await _initPermission();

    if (hasPermission) {
      log('Start permanent service android notification listener service');

      // await _startPermanentService();
      await startNotificationService();

      Settings settings = getSettingInstance();

      if (settings.ownedApp == null) {
        Timer(const Duration(seconds: 5), () {
          // _settingController.verifyOwnedApp();
        });
      }
    }

    // recordsBox = await Hive.openBox<Record>('records');
    // records.addAll(recordsBox.values);
  }

  static showNecessaryPermissionDialog({
    VoidCallback? onConfirm,
    required String title,
    required WillPopCallback onWillPop,
  }) {
    return Get.defaultDialog(
      onWillPop: onWillPop,
      titlePadding: const EdgeInsets.only(top: 20),
      titleStyle: const TextStyle(fontSize: 22),
      contentPadding: const EdgeInsets.symmetric(horizontal: 25, vertical: 8),
      title: title,
      content: Text(
        "Note Bene! This app requires notification listener permission and battery optimization turned off to work.".tr,
        style: const TextStyle(fontSize: 16),
      ),
      confirm: TextButton(
        child: const Text(
          "Ok",
          style: TextStyle(fontSize: 20),
        ),
        onPressed: () {
          if (onConfirm != null) {
            onConfirm();
          }
        },
      ),
    );
  }

  hasNotificationListenerPermission() async {
    return await NotificationsListener.hasPermission ?? false;
  }

  hasBatteryOptimizationDisabledPermission() async {
    return await DisableBatteryOptimization.isBatteryOptimizationDisabled ?? false;
  }

  Future<bool> _initPermission() async {
    bool isNotificationListenerEnabled = await hasNotificationListenerPermission();
    bool isBatteryOptimizationDisabled = await hasBatteryOptimizationDisabledPermission();

    if (isNotificationListenerEnabled && isBatteryOptimizationDisabled) {
      return true;
    }

    if (!isNotificationListenerEnabled) {
      await showNecessaryPermissionDialog(
        title: 'Notification Listener'.tr,
        onWillPop: () async {
          return await hasNotificationListenerPermission();
        },
        onConfirm: () async {
          if (await hasNotificationListenerPermission()) {
            Get.back();
          } else {
            NotificationsListener.openPermissionSettings();
          }
        },
      );
    }

    if (!isBatteryOptimizationDisabled) {
      await showNecessaryPermissionDialog(
        title: 'Battery Optimization !'.tr,
        onWillPop: () async {
          return await hasBatteryOptimizationDisabledPermission();
        },
        onConfirm: () async {
          if (await hasBatteryOptimizationDisabledPermission()) {
            Get.back();
          } else {
            await DisableBatteryOptimization.showDisableBatteryOptimizationSettings();
          }
        },
      );
    }

    return true;
  }

  startNotificationService() async {
    var isRunning = await NotificationsListener.isRunning ?? false;

    if (!isRunning) {
      bool isSuccess = await NotificationsListener.startService(
            foreground: false,
            title: "Listener Running",
          ) ??
          false;
      if (isSuccess) {
        log('Start listening', name: 'NotificationService');
      }
    }
    isListening.value = true;
  }

  exportXlsx() async {
    var exportRecords = records.reversed.toList();
    int c = 100;
    int n = (records.length / c).ceil();
    var now = DateTime.now();
    String nowString = '${now.year}-${now.month}-${now.day}_${now.hour}-${now.minute}-${now.second}_${UniqueKey().toString()}';
    Directory tmp = await getTemporaryDirectory();
    String tmpPath = '${tmp.path}/$nowString';

    List<String> columnNames = ["uid", "App Name", "Package Name", "Amount", "Create Time"];

    try {
      if (!Directory(tmpPath).existsSync()) {
        Directory(tmpPath).createSync();
      }

      if (!Directory(documentsDirectory).existsSync()) {
        Directory(documentsDirectory).createSync();
      }

      for (var i = 0; i < n; i++) {
        final Workbook workbook = Workbook();
        final Worksheet sheet = workbook.worksheets[0];
        sheet.showGridlines = true;
        sheet.enableSheetCalculations();
        var e = (i + 1) * c;
        var start = i * c, end = records.length < e ? (records.length % c) : e;
        var recordList = exportRecords.getRange(start, end);

        for (var k = 0; k < columnNames.length; k++) {
          final Range range = sheet.getRangeByName('${String.fromCharCode(65 + k)}1');
          range.setText(columnNames[k]);
          range.autoFit();
        }

        for (var r = 0; r < recordList.length; r++) {
          Record record = recordList.elementAt(r);

          for (var j = 0; j < columnNames.length; j++) {
            final Range range = sheet.getRangeByName('${String.fromCharCode(65 + j)}${2 + r}');
            switch (j) {
              case 0:
                range.setText(record.uid);
                break;
              case 1:
                range.setText(record.appName);
                break;
              case 2:
                range.setText(record.packageName);
                break;
              case 3:
                range.setText(record.amount);
                break;
              case 4:
                range.setDateTime(record.createTime);
                break;
              default:
            }
            range.autoFit();
          }
        }

        final List<int> bytes = workbook.saveAsStream();
        File("$tmpPath/$start~$end.xlsx").writeAsBytes(bytes);
        workbook.dispose();
      }

      await ZipFile.createFromDirectory(sourceDir: Directory(tmpPath), zipFile: File('$documentsDirectory/$nowString.zip'), recurseSubDirs: true);
      Fluttertoast.showToast(msg: 'Save to the $documentsDirectory');
    } catch (e) {
      Fluttertoast.showToast(msg: e.toString());
    }
  }
}
