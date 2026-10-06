-- تشغيل على السيرفر (Linux) بعد استيراد قاعدة من Windows/XAMPP
-- phpMyAdmin يعرض الأسماء بأحرف صغيرة؛ Laravel يتوقع camelCase لبعض الجداول.
-- نفّذ: mysql -u syriataxi -p syriataxi < fix_mysql_table_names_linux.sql

USE syriataxi;

-- إن ظهر خطأ "Unknown table" فالجدول مُسمّى مسبقاً — تجاهل السطر.

RENAME TABLE cartypes TO carTypes;
RENAME TABLE requesthistories TO requestHistories;
RENAME TABLE useddiscounts TO usedDiscounts;
RENAME TABLE apiaccesses TO apiAccesses;
RENAME TABLE userapiaccesses TO userApiAccesses;
