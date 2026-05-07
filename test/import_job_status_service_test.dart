import 'package:clarity/features/transactions/application/import_job_status_service.dart';
import 'package:clarity/features/transactions/data/csv_import_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('failed import progress remains visible until dismissed', () {
    final service = ImportJobStatusService();
    var notifications = 0;

    service.applyCsvImportProgress(
      CsvImportProgress.failed(const FormatException('Bad CSV')),
      notifyStatusChanged: () => notifications += 1,
    );

    expect(service.importRunning, isFalse);
    expect(service.importSnackMessage, contains('Could not import this CSV'));
    expect(
      service.persistentImportMessage,
      contains('Could not import this CSV'),
    );
    expect(service.persistentImportMessageIsError, isTrue);

    service.dismissPersistentImportMessage(
      notifyStatusChanged: () => notifications += 1,
    );

    expect(service.persistentImportMessage, isNull);
    expect(service.persistentImportMessageIsError, isFalse);
    expect(notifications, 2);
  });
}
