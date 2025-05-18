#include <WiFi.h>
#include <TinyGPS++.h>
#include <ESPSupabase.h>       // or use HTTPClient if you prefer raw REST
#include "secrets.h"

// ——— Instantiate once globally ———
Supabase supabase;

// --- GPS & Serial config ---
#define RXD2 16
#define TXD2 17
#define GPS_BAUD 9600

HardwareSerial gpsSerial(2);
TinyGPSPlus gps;

void setup() {
  Serial.begin(115200);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("\nWiFi connected!");
  gpsSerial.begin(GPS_BAUD, SERIAL_8N1, RXD2, TXD2);
  supabase.begin(SUPABASE_URL, SUPABASE_ANON);
}

void loop() {
  while (gpsSerial.available()) {
    if (gps.encode(gpsSerial.read()) && gps.location.isValid()) {
      float latitude = gps.location.lat();
      float longitude = gps.location.lng();
      Serial.printf("Got fix: %.6f, %.6f\n", latitude, longitude);

      String payload = String("{\"latitude\":") + latitude 
               + String(",\"longitude\":") + longitude 
               + String(",\"vehicleId\":\"") + VEHICLE_ID 
               + String("\"}");

      // Insert into Supabase
      supabase.insert("Location", payload, false);

      delay(10000); // send every 10s
    }
  }
}
