package com.citiride.citiride

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val locationPermissionChannel = "citiride/location_permission"
    private val googleMapsConfigChannel = "citiride/google_maps_config"
    private val locationPermissionRequestCode = 5107
    private var pendingLocationPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            locationPermissionChannel,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestWhenInUse" -> requestLocationPermission(result)
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            googleMapsConfigChannel,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "apiKey" -> result.success(googleMapsApiKey())
                else -> result.notImplemented()
            }
        }
    }

    private fun googleMapsApiKey(): String? {
        val appInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.getApplicationInfo(
                packageName,
                PackageManager.ApplicationInfoFlags.of(PackageManager.GET_META_DATA.toLong()),
            )
        } else {
            @Suppress("DEPRECATION")
            packageManager.getApplicationInfo(packageName, PackageManager.GET_META_DATA)
        }

        return appInfo.metaData?.getString("com.google.android.geo.API_KEY")
    }

    private fun requestLocationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M || hasLocationPermission()) {
            result.success(true)
            return
        }

        if (pendingLocationPermissionResult != null) {
            result.success(false)
            return
        }

        pendingLocationPermissionResult = result
        requestPermissions(
            arrayOf(
                Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.ACCESS_COARSE_LOCATION,
            ),
            locationPermissionRequestCode,
        )
    }

    private fun hasLocationPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return true
        }

        return checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED ||
            checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)

        if (requestCode != locationPermissionRequestCode) {
            return
        }

        val granted = grantResults.any { it == PackageManager.PERMISSION_GRANTED }
        pendingLocationPermissionResult?.success(granted)
        pendingLocationPermissionResult = null
    }
}