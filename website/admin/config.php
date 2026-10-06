<?php

declare(strict_types=1);

session_start();

const SITE_ADMIN_PASSWORD = 'Gstaxi@2026';

function site_root(): string
{
    return dirname(__DIR__);
}

function content_path(): string
{
    return site_root().DIRECTORY_SEPARATOR.'data'.DIRECTORY_SEPARATOR.'content.json';
}

function uploads_dir(): string
{
    return site_root().DIRECTORY_SEPARATOR.'uploads';
}

function load_content(): array
{
    $path = content_path();
    if (! is_file($path)) {
        return [];
    }
    $raw = file_get_contents($path);
    $data = json_decode((string) $raw, true);

    return is_array($data) ? $data : [];
}

function persist_content(array $data): void
{
    $dir = dirname(content_path());
    if (! is_dir($dir) && ! mkdir($dir, 0777, true) && ! is_dir($dir)) {
        json_out(['success' => false, 'message' => 'تعذر إنشاء مجلد data'], 500);
    }
    @chmod($dir, 0777);
    $path = content_path();
    $json = json_encode($data, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT);
    if ($json === false) {
        json_out(['success' => false, 'message' => 'تعذر ترميز المحتوى'], 500);
    }
    $ok = @file_put_contents($path, $json, LOCK_EX);
    @chmod($path, 0666);
    if ($ok === false) {
        json_out([
            'success' => false,
            'message' => 'تعذر حفظ content.json — اجعل مجلد data قابلاً للكتابة: chmod 777 public/site/data',
        ], 500);
    }
}

function save_content(array $data): bool
{
    persist_content($data);

    return true;
}

function public_media_url(string $relative): string
{
    $relative = ltrim(str_replace('\\', '/', $relative), '/');
    $script = str_replace('\\', '/', (string) ($_SERVER['SCRIPT_NAME'] ?? '/site/admin/api.php'));
    $base = preg_replace('#/admin/api\\.php$#', '', $script) ?: '/site';

    return rtrim($base, '/').'/'.$relative.'?v='.time();
}

function is_logged_in(): bool
{
    return ! empty($_SESSION['site_admin']);
}

function require_login(): void
{
    if (! is_logged_in()) {
        http_response_code(401);
        echo json_encode(['success' => false, 'message' => 'سجّل الدخول أولاً']);
        exit;
    }
}

function json_out(array $payload, int $code = 200): void
{
    http_response_code($code);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode($payload, JSON_UNESCAPED_UNICODE);
    exit;
}

function new_id(string $prefix): string
{
    return $prefix.'_'.bin2hex(random_bytes(4));
}

function save_upload(string $field): ?string
{
    if (empty($_FILES[$field]) || ! is_array($_FILES[$field])) {
        return null;
    }
    $file = $_FILES[$field];
    $err = (int) ($file['error'] ?? UPLOAD_ERR_NO_FILE);
    if ($err === UPLOAD_ERR_NO_FILE || ($file['tmp_name'] ?? '') === '') {
        return null;
    }
    if ($err !== UPLOAD_ERR_OK) {
        $map = [
            UPLOAD_ERR_INI_SIZE => 'حجم الملف أكبر من حد PHP (upload_max_filesize)',
            UPLOAD_ERR_FORM_SIZE => 'حجم الملف أكبر من حد النموذج',
            UPLOAD_ERR_PARTIAL => 'رُفع الملف جزئياً فقط — أعد المحاولة',
            UPLOAD_ERR_NO_TMP_DIR => 'مجلد مؤقت للرفع غير موجود على السيرفر',
            UPLOAD_ERR_CANT_WRITE => 'تعذر الكتابة في القرص',
            UPLOAD_ERR_EXTENSION => 'إضافة PHP منعت الرفع',
        ];
        json_out(['success' => false, 'message' => $map[$err] ?? 'فشل رفع الملف'], 422);
    }
    if (! is_uploaded_file((string) $file['tmp_name'])) {
        json_out(['success' => false, 'message' => 'ملف الرفع غير صالح'], 422);
    }
    if (($file['size'] ?? 0) > 12 * 1024 * 1024) {
        json_out(['success' => false, 'message' => 'الصورة أكبر من 12 م.ب'], 422);
    }

    $ext = strtolower(pathinfo((string) $file['name'], PATHINFO_EXTENSION));
    $mime = '';
    if (class_exists('finfo')) {
        $mime = (string) (new \finfo(FILEINFO_MIME_TYPE))->file($file['tmp_name']);
    }
    $mimeExt = [
        'image/jpeg' => 'jpg',
        'image/png' => 'png',
        'image/webp' => 'webp',
        'image/gif' => 'gif',
    ];
    if (isset($mimeExt[$mime])) {
        $ext = $mimeExt[$mime];
    }
    if (! in_array($ext, ['jpg', 'jpeg', 'png', 'webp', 'gif'], true)) {
        json_out(['success' => false, 'message' => 'صيغة الصورة غير مدعومة (jpg / png / webp / gif)'], 422);
    }
    if ($ext === 'jpeg') {
        $ext = 'jpg';
    }

    $dir = uploads_dir();
    if (! is_dir($dir) && ! mkdir($dir, 0777, true) && ! is_dir($dir)) {
        json_out(['success' => false, 'message' => 'تعذر إنشاء مجلد uploads — أنشئه يدوياً على السيرفر'], 500);
    }
    @chmod($dir, 0777);
    if (! is_writable($dir)) {
        json_out([
            'success' => false,
            'message' => 'مجلد uploads غير قابل للكتابة. على السيرفر نفّذ: chmod 777 public/site/uploads',
        ], 500);
    }

    $name = date('Ymd_His').'_'.bin2hex(random_bytes(3)).'.'.$ext;
    $dest = $dir.DIRECTORY_SEPARATOR.$name;
    $ok = @move_uploaded_file($file['tmp_name'], $dest);
    if (! $ok) {
        $ok = @copy($file['tmp_name'], $dest);
    }
    if (! $ok || ! is_file($dest)) {
        json_out([
            'success' => false,
            'message' => 'تعذر حفظ الملف في uploads — تحقق من صلاحيات المجلد على السيرفر',
        ], 500);
    }
    @chmod($dest, 0644);

    return public_media_url('uploads/'.$name);
}
