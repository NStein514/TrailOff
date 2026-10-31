package com.example.trailoff

import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.hardware.GeomagneticField
import android.view.Surface
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import kotlin.math.cos
import kotlin.math.sin

class MainActivity : FlutterActivity(), SensorEventListener, EventChannel.StreamHandler {
    private lateinit var sensors: SensorManager
    private var sink: EventChannel.EventSink? = null
    private var declination = 0.0

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        sensors = getSystemService(SENSOR_SERVICE) as SensorManager
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "trailoff/sky_orientation").setStreamHandler(this)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sensors.unregisterListener(this)
        sink = events
        val args = arguments as? Map<*, *> ?: emptyMap<Any, Any>()
        declination = Math.toRadians(GeomagneticField(
            (args["latitude"] as? Number)?.toFloat() ?: 0f,
            (args["longitude"] as? Number)?.toFloat() ?: 0f,
            (args["altitude"] as? Number)?.toFloat() ?: 0f,
            System.currentTimeMillis()).declination.toDouble())
        // Rotation vector fuses gyro, accelerometer and magnetometer. The game
        // rotation vector deliberately has no compass reference and is unsuitable.
        val sensor = sensors.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
        if (sensor == null || !sensors.registerListener(this, sensor, 50000)) {
            events.error("unavailable", "Compass orientation is unavailable", null)
        }
    }

    override fun onCancel(arguments: Any?) {
        sensors.unregisterListener(this)
        sink = null
    }

    override fun onSensorChanged(event: SensorEvent) {
        if (event.accuracy == SensorManager.SENSOR_STATUS_UNRELIABLE) return
        val rotation = FloatArray(9)
        SensorManager.getRotationMatrixFromVector(rotation, event.values)
        val remapped = FloatArray(9)
        @Suppress("DEPRECATION")
        val displayRotation = windowManager.defaultDisplay.rotation
        val axes = when (displayRotation) {
            Surface.ROTATION_90 -> Pair(SensorManager.AXIS_Y, SensorManager.AXIS_MINUS_X)
            Surface.ROTATION_180 -> Pair(SensorManager.AXIS_MINUS_X, SensorManager.AXIS_MINUS_Y)
            Surface.ROTATION_270 -> Pair(SensorManager.AXIS_MINUS_Y, SensorManager.AXIS_X)
            else -> Pair(SensorManager.AXIS_X, SensorManager.AXIS_Y)
        }
        SensorManager.remapCoordinateSystem(rotation, axes.first, axes.second, remapped)
        val c = cos(declination)
        val s = sin(declination)
        // Transpose device->world, then convert true ENU to magnetic ENU.
        val matrix = (0..2).flatMap { row ->
            listOf(remapped[row] * c + remapped[3 + row] * s,
                -remapped[row] * s + remapped[3 + row] * c,
                remapped[6 + row].toDouble())
        }
        sink?.success(matrix)
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
    override fun onPause() {
        sensors.unregisterListener(this)
        super.onPause()
    }
    override fun onDestroy() {
        sensors.unregisterListener(this)
        sink = null
        super.onDestroy()
    }
}
