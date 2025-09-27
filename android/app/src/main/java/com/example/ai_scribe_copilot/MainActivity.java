package com.example.ai_scribe_copilot;

import android.content.Intent;
import android.os.Bundle;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

public class MainActivity extends FlutterActivity {
    private static final String CHANNEL = "com.example.ai_scribe_copilot/recording";
    private MethodChannel methodChannel;

    @Override
    public void configureFlutterEngine(FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        
        methodChannel = new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL);
        methodChannel.setMethodCallHandler((call, result) -> {
            switch (call.method) {
                case "startForegroundService":
                    startForegroundService();
                    result.success("Foreground service started");
                    break;
                case "stopForegroundService":
                    stopForegroundService();
                    result.success("Foreground service stopped");
                    break;
                default:
                    result.notImplemented();
                    break;
            }
        });
    }

    private void startForegroundService() {
        Intent serviceIntent = new Intent(this, RecordingForegroundService.class);
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            startForegroundService(serviceIntent);
        } else {
            startService(serviceIntent);
        }
    }

    private void stopForegroundService() {
        Intent serviceIntent = new Intent(this, RecordingForegroundService.class);
        stopService(serviceIntent);
    }
}
