<?php

declare(strict_types=1);

require __DIR__.'/config.php';

header('Content-Type: application/json; charset=utf-8');

$action = (string) ($_GET['action'] ?? $_POST['action'] ?? '');

if ($action === 'content') {
    header('Cache-Control: no-store, no-cache, must-revalidate');
    json_out(['success' => true, 'data' => load_content()]);
}

if ($action === 'login') {
    $pass = (string) ($_POST['password'] ?? '');
    if (! hash_equals(SITE_ADMIN_PASSWORD, $pass)) {
        json_out(['success' => false, 'message' => 'كلمة المرور غير صحيحة'], 401);
    }
    $_SESSION['site_admin'] = true;
    json_out(['success' => true]);
}

if ($action === 'logout') {
    $_SESSION = [];
    session_destroy();
    json_out(['success' => true]);
}

if ($action === 'me') {
    json_out(['success' => true, 'logged_in' => is_logged_in()]);
}

require_login();

$data = load_content();

if ($action === 'save_links') {
    $data['stores'] = [
        'play' => trim((string) ($_POST['play'] ?? '')),
        'apple' => trim((string) ($_POST['apple'] ?? '')),
        'apk' => trim((string) ($_POST['apk'] ?? '')),
    ];
    $data['social'] = [
        'instagram' => trim((string) ($_POST['instagram'] ?? '')),
        'facebook' => trim((string) ($_POST['facebook'] ?? '')),
        'whatsapp' => trim((string) ($_POST['whatsapp'] ?? '')),
        'telegram' => trim((string) ($_POST['telegram'] ?? '')),
    ];
    save_content($data);
    json_out(['success' => true, 'data' => $data]);
}

if ($action === 'add_carousel') {
    $src = save_upload('image');
    if (! $src) {
        $src = trim((string) ($_POST['url'] ?? ''));
    }
    if ($src === '') {
        json_out(['success' => false, 'message' => 'ارفع صورة أو الصق رابطاً'], 422);
    }
    $data['carousel'][] = [
        'id' => new_id('c'),
        'src' => $src,
        'kicker' => trim((string) ($_POST['kicker'] ?? '')),
        'title' => trim((string) ($_POST['title'] ?? '')),
        'lead' => trim((string) ($_POST['lead'] ?? '')),
    ];
    save_content($data);
    json_out(['success' => true, 'data' => $data]);
}

if ($action === 'save_hero') {
    $data['hero'] = [
        'kicker' => trim((string) ($_POST['kicker'] ?? '')),
        'title' => trim((string) ($_POST['title'] ?? '')),
        'lead' => trim((string) ($_POST['lead'] ?? '')),
    ];
    save_content($data);
    json_out(['success' => true, 'data' => $data]);
}

if ($action === 'update_carousel') {
    $id = (string) ($_POST['id'] ?? '');
    $found = false;
    foreach ($data['carousel'] as &$row) {
        if (($row['id'] ?? '') !== $id) {
            continue;
        }
        $found = true;
        $row['kicker'] = trim((string) ($_POST['kicker'] ?? ''));
        $row['title'] = trim((string) ($_POST['title'] ?? ''));
        $row['lead'] = trim((string) ($_POST['lead'] ?? ''));
        $newSrc = save_upload('image');
        if (! $newSrc) {
            $url = trim((string) ($_POST['url'] ?? ''));
            if ($url !== '') {
                $newSrc = $url;
            }
        }
        if ($newSrc) {
            $row['src'] = $newSrc;
        }
        break;
    }
    unset($row);
    if (! $found) {
        json_out(['success' => false, 'message' => 'الشريحة غير موجودة'], 404);
    }
    save_content($data);
    json_out(['success' => true, 'data' => $data]);
}

if ($action === 'delete_carousel') {
    json_out([
        'success' => false,
        'message' => 'حذف شرائح الكاروسيل معطّل. يمكن استبدال الصورة فقط.',
    ], 403);
}

if ($action === 'add_news') {
    $image = save_upload('image');
    if (! $image) {
        $image = trim((string) ($_POST['image_url'] ?? ''));
    }
    $title = trim((string) ($_POST['title'] ?? ''));
    $text = trim((string) ($_POST['text'] ?? ''));
    if ($title === '' || $text === '' || $image === '') {
        json_out(['success' => false, 'message' => 'أدخل العنوان والنص والصورة'], 422);
    }
    array_unshift($data['news'], [
        'id' => new_id('n'),
        'title' => $title,
        'date' => trim((string) ($_POST['date'] ?? date('Y-m-d'))),
        'text' => $text,
        'image' => $image,
    ]);
    save_content($data);
    json_out(['success' => true, 'data' => $data]);
}

if ($action === 'delete_news') {
    $id = (string) ($_POST['id'] ?? '');
    $data['news'] = array_values(array_filter(
        $data['news'] ?? [],
        static fn ($row) => ($row['id'] ?? '') !== $id
    ));
    save_content($data);
    json_out(['success' => true, 'data' => $data]);
}

if ($action === 'update_news') {
    $id = (string) ($_POST['id'] ?? '');
    $title = trim((string) ($_POST['title'] ?? ''));
    $text = trim((string) ($_POST['text'] ?? ''));
    if ($title === '' || $text === '') {
        json_out(['success' => false, 'message' => 'أدخل العنوان والنص'], 422);
    }
    $found = false;
    foreach ($data['news'] as &$row) {
        if (($row['id'] ?? '') !== $id) {
            continue;
        }
        $found = true;
        $row['title'] = $title;
        $row['text'] = $text;
        $row['date'] = trim((string) ($_POST['date'] ?? ($row['date'] ?? '')));
        $newImage = save_upload('image');
        if (! $newImage) {
            $url = trim((string) ($_POST['image_url'] ?? ''));
            if ($url !== '') {
                $newImage = $url;
            }
        }
        if ($newImage) {
            $row['image'] = $newImage;
        }
        break;
    }
    unset($row);
    if (! $found) {
        json_out(['success' => false, 'message' => 'الخبر غير موجود'], 404);
    }
    save_content($data);
    json_out(['success' => true, 'data' => $data]);
}

if ($action === 'add_ad') {
    $title = trim((string) ($_POST['title'] ?? ''));
    $text = trim((string) ($_POST['text'] ?? ''));
    if ($title === '' || $text === '') {
        json_out(['success' => false, 'message' => 'أدخل عنوان الإعلان ونصّه'], 422);
    }
    array_unshift($data['ads'], [
        'id' => new_id('a'),
        'tag' => trim((string) ($_POST['tag'] ?? 'عرض')),
        'title' => $title,
        'text' => $text,
        'date' => trim((string) ($_POST['date'] ?? '')),
    ]);
    save_content($data);
    json_out(['success' => true, 'data' => $data]);
}

if ($action === 'delete_ad') {
    $id = (string) ($_POST['id'] ?? '');
    $data['ads'] = array_values(array_filter(
        $data['ads'] ?? [],
        static fn ($row) => ($row['id'] ?? '') !== $id
    ));
    save_content($data);
    json_out(['success' => true, 'data' => $data]);
}

if ($action === 'update_ad') {
    $id = (string) ($_POST['id'] ?? '');
    $title = trim((string) ($_POST['title'] ?? ''));
    $text = trim((string) ($_POST['text'] ?? ''));
    if ($title === '' || $text === '') {
        json_out(['success' => false, 'message' => 'أدخل عنوان الإعلان ونصّه'], 422);
    }
    $found = false;
    foreach ($data['ads'] as &$row) {
        if (($row['id'] ?? '') !== $id) {
            continue;
        }
        $found = true;
        $row['tag'] = trim((string) ($_POST['tag'] ?? ($row['tag'] ?? 'عرض')));
        $row['title'] = $title;
        $row['text'] = $text;
        $row['date'] = trim((string) ($_POST['date'] ?? ($row['date'] ?? '')));
        break;
    }
    unset($row);
    if (! $found) {
        json_out(['success' => false, 'message' => 'الإعلان غير موجود'], 404);
    }
    save_content($data);
    json_out(['success' => true, 'data' => $data]);
}

json_out(['success' => false, 'message' => 'إجراء غير معروف'], 400);
