package com.syriataxi.syriatax;

import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.media.AudioAttributes;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;

import io.flutter.embedding.android.FlutterActivity;

public class MainActivity extends FlutterActivity {

    /** قناة إشعارات FCM الافتراضية — يجب أن تطابق AndroidManifest والخادم و android_notification_channels.dart. */
    public static final String FCM_CHANNEL_ID = "syriataxi_notify_v3";
    public static final String FCM_CHANNEL_NAME = "إشعارات سوريا تاكسي";

    public static final String RIDE_OFFERS_CHANNEL_ID = "syriataxi_ride_offers_v3";
    public static final String RIDE_OFFERS_CHANNEL_NAME = "طلبات الرحلات";

    /** صوت القناة لا يتغيّر بعد إنشائها — تغيير النغمة يتطلّب معرّف قناة جديد وحذف القديمة. */
    private static final String[] LEGACY_CHANNEL_IDS = {
            "syriataxi_high",
            "syriataxi_ride_offers",
            "syriataxi_ride_offers_v2",
    };

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        createNotificationChannels();
    }

    private void createNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return;
        }
        NotificationManager manager = getSystemService(NotificationManager.class);
        if (manager == null) {
            return;
        }
        for (String id : LEGACY_CHANNEL_IDS) {
            manager.deleteNotificationChannel(id);
        }

        AudioAttributes notifAttrs = new AudioAttributes.Builder()
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                .build();

        NotificationChannel fcm = new NotificationChannel(
                FCM_CHANNEL_ID,
                FCM_CHANNEL_NAME,
                NotificationManager.IMPORTANCE_HIGH
        );
        fcm.setDescription("حجز مسبق وتنبيهات التطبيق");
        fcm.enableVibration(true);
        fcm.enableLights(true);
        fcm.setSound(rawSound("gs_notify"), notifAttrs);
        manager.createNotificationChannel(fcm);

        NotificationChannel offers = new NotificationChannel(
                RIDE_OFFERS_CHANNEL_ID,
                RIDE_OFFERS_CHANNEL_NAME,
                NotificationManager.IMPORTANCE_HIGH
        );
        offers.setDescription("رنين الطلبات الجديدة للسائق");
        offers.enableVibration(true);
        offers.enableLights(true);
        offers.setSound(rawSound("gs_ringtone"), notifAttrs);
        manager.createNotificationChannel(offers);
    }

    private Uri rawSound(String name) {
        return Uri.parse("android.resource://" + getPackageName() + "/raw/" + name);
    }
}
