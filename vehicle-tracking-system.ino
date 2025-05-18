#include <WiFi.h>
#include <TinyGPS++.h>
#include <ESPSupabase.h>
#include "secrets.h" // For SUPABASE_URL, SUPABASE_ANON, WIFI_SSID, and WIFI_PASSWORD

// ——— Instantiate once globally ———
Supabase supabase;

// —– GPS & Serial config —–
#define RXD2      16
#define TXD2      17
#define GPS_BAUD  9600

HardwareSerial gpsSerial(2);
TinyGPSPlus    gps;

void setup() {
  Serial.begin(115200);

  // Connect Wi-Fi
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("\nWiFi connected!");

  // Start GPS serial
  gpsSerial.begin(GPS_BAUD, SERIAL_8N1, RXD2, TXD2);

  // Init Supabase
  supabase.begin(SUPABASE_URL, SUPABASE_ANON);
}

void loop() {
  // Feed GPS characters into TinyGPS++
  while (gpsSerial.available()) {
    if (gps.encode(gpsSerial.read())) {
      // Only process when we have a valid fix
      if (gps.location.isValid()) {
        // 1) Extract all metrics
        float latitude   = gps.location.lat();
        float longitude  = gps.location.lng();
        float speedInKmph  = gps.speed.isValid() ? gps.speed.kmph() : NAN;
        float courseDegree  = gps.course.isValid() ? gps.course.deg() : NAN;
        float altitudeInMeters  = gps.altitude.isValid() ? gps.altitude.meters() : NAN;
        int   numberOfSatellitesUsed   = gps.satellites.isValid() ? gps.satellites.value() : 0;
        // Date/time only if both valid
        String accessDateTime = "";
        if (gps.date.isValid() && gps.time.isValid()) {
          char buf[32];
          snprintf(
            buf, 
            sizeof(buf),
            "%04u-%02u-%02uT%02u:%02u:%02uZ",
            gps.date.year(),
            gps.date.month(),
            gps.date.day(),
            gps.time.hour(),
            gps.time.minute(),
            gps.time.second()
          );
          accessDateTime = String(buf);
        }

        // 2) Print to Serial
        Serial.printf("Fix: %.6f, %.6f\n", latitude, longitude);
        if (!isnan(speedInKmph))
          Serial.printf(" Speed: %.1f km/h\n", speedInKmph);
        if (!isnan(courseDegree))
          Serial.printf(" Course: %.1f°\n", courseDegree);
        if (!isnan(altitudeInMeters))
          Serial.printf(" Altitude: %.1f m\n", altitudeInMeters);
        Serial.printf(" Number of satellites used: %d\n", numberOfSatellitesUsed);
        if (accessDateTime.length())
          Serial.printf(" UTC Date/Time: %s\n", accessDateTime.c_str());

        // 3) Build JSON payload
        String payload = String("{") +
          "\"latitude\":"               + String(latitude, 6)            + "," +
          "\"longitude\":"              + String(longitude, 6)           + "," +
          "\"speedInKmph\":"            + String(speedInKmph, 1)         + "," +
          "\"courseDegree\":"           + String(courseDegree, 1)        + "," +
          "\"altitudeInMeters\":"       + String(altitudeInMeters, 1)    + "," +
          "\"numberOfSatellitesUsed\":" + String(numberOfSatellitesUsed) + "," +
          "\"accessDateTime\":\""       + accessDateTime                 + "\"," +
          "\"vehicleId\":\""            + VEHICLE_ID                     + "\"" +
        "}";

        // 4) Send to Supabase
        int status = supabase.insert("TrackingData", payload, false);
        Serial.printf("Supabase insert status: %d\n\n", status);

        // Wait before next sample
        delay(10000);
      }
    }
  }
}
