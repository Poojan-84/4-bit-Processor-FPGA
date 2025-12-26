#include <SPI.h>
#include "Shrike.h"

// --- Configuration ---
#define BITSTREAM_FILE "/4_bit_cpu.bin"

// --- Pin Definitions ---
#define PIN_MISO  0
#define PIN_CS    1
#define PIN_SCK   2
#define PIN_MOSI  3
#define PIN_RST   14 
#define LED_PIN   25

// --- CPU Command Definitions ---
#define INSTR_LOADPROG  0
#define INSTR_LOADDATA  1
#define INSTR_SETRUNPT  2
#define INSTR_RUNPROG   3

ShrikeFlash shrike;
bool fpga_ready = false;

void setup() {
  Serial.begin(115200);
  pinMode(LED_PIN, OUTPUT);
  
  // Wait for Serial
  while (!Serial) {
    digitalWrite(LED_PIN, !digitalRead(LED_PIN));
    delay(100);
  }
  
  Serial.println("\n\n=== Shrike Lite: System Restart ===");
  
  // 1. Flash FPGA
  Serial.print("1. Flashing FPGA from MCU memory ");
  shrike.begin();
  if (shrike.flash(BITSTREAM_FILE)) {
    Serial.println("SUCCESS");
    fpga_ready = true;
  } else {
    Serial.println("FAILED!");
    Serial.println("   -> Check: Did you use 'Pico LittleFS Data Upload'?");
    Serial.println("   -> Check: Is file named '4_bit_cpu.bin' in data folder?");
  }
  
  // 2. Setup SPI Controller
  SPI.setRX(PIN_MISO);
  SPI.setCS(PIN_CS);
  SPI.setSCK(PIN_SCK);
  SPI.setTX(PIN_MOSI);
  SPI.begin();
  SPI.beginTransaction(SPISettings(1000000, MSBFIRST, SPI_MODE0));
  
  pinMode(PIN_RST, OUTPUT);
  digitalWrite(PIN_RST, HIGH); 
  delay(100);
}

void loop() {
  digitalWrite(LED_PIN, HIGH);
  Serial.println("\n--- Starting Test Loop ---");
  
  if (fpga_ready) {
    run_cpu_test();
  } else {
    Serial.println("Skipping test (FPGA not configured).");
  }
  
  digitalWrite(LED_PIN, LOW);
  delay(3000); // Wait 3 seconds before repeating
}

// ================================================================
//                      CPU CONTROLLER LOGIC
// ================================================================

// Send Packet: [Data 4b] [Instr 2b] [Reset 1b] [Step 1b]
void send_packet(uint8_t data, uint8_t instr, bool reset, bool step) {
  uint8_t packet = 0;
  packet |= (data & 0x0F) << 4;
  packet |= (instr & 0x03) << 2;
  packet |= (reset & 0x01) << 1;
  packet |= (step & 0x01) << 0;
  
  digitalWrite(PIN_CS, LOW);
  delayMicroseconds(10); // Small delay after CS low
  SPI.transfer(packet);
  digitalWrite(PIN_CS, HIGH);
  
  delayMicroseconds(200); // Increased delay for FPGA processing
}

// Read State from MISO
void print_cpu_state() {
  digitalWrite(PIN_CS, LOW);
  delayMicroseconds(10);
  uint8_t response = SPI.transfer(0x00); 
  digitalWrite(PIN_CS, HIGH);
  
  uint8_t cpu_reg = response >> 4;
  uint8_t cpu_pc = response & 0x0F;
  
  Serial.printf("   [State] PC: %d | REG: %d\n", cpu_pc, cpu_reg);
  
  delayMicroseconds(100);
}

// Test Sequence: Calculate 2 + 3 = 5
void run_cpu_test() {
  Serial.println("\n=== Testing CPU: 2 + 3 ===\n");
  
  // ---- STEP 1: Reset CPU ----
  Serial.println("Step 1: Resetting CPU...");
  send_packet(0, 0, true, false);  // Assert reset
  delay(10);
  send_packet(0, 0, false, false); // Release reset
  delay(10);
  print_cpu_state(); // Should show PC=0, REG=0
  
  // ---- STEP 2: Load PROGRAM Memory ----
  Serial.println("\nStep 2: Loading Program Memory...");
  
  // PC=0: Write LOAD instruction (opcode 0)
  Serial.println("  Writing prog[0] = LOAD (0)");
  send_packet(0, INSTR_LOADPROG, false, true); // prog[0] = 0 (LOAD), PC→1
  
  // PC=1: Write ADD instruction (opcode 2)
  Serial.println("  Writing prog[1] = ADD (2)");
  send_packet(2, INSTR_LOADPROG, false, true); // prog[1] = 2 (ADD), PC→2
  
  print_cpu_state(); // Should show PC=2
  
  // ---- STEP 3: Load DATA Memory ----
  Serial.println("\nStep 3: Loading Data Memory...");
  
  // Reset PC to 0 first
  Serial.println("  Resetting PC to 0");
  send_packet(0, INSTR_SETRUNPT, false, true); // PC = 0
  
  // PC=0: Write data value 2
  Serial.println("  Writing data[0] = 2");
  send_packet(2, INSTR_LOADDATA, false, true); // data[0] = 2, PC→1
  
  // PC=1: Write data value 3
  Serial.println("  Writing data[1] = 3");
  send_packet(3, INSTR_LOADDATA, false, true); // data[1] = 3, PC→2
  
  print_cpu_state(); // Should show PC=2
  
  // ---- STEP 4: Execute Program ----
  Serial.println("\nStep 4: Executing Program...");
  
  // Reset PC to start of program
  Serial.println("  Setting PC = 0");
  send_packet(0, INSTR_SETRUNPT, false, true); // PC = 0
  delay(10);
  print_cpu_state(); // Should show PC=0, REG=0
  
  // Execute instruction at PC=0 (LOAD 2)
  Serial.println("\n  Executing: LOAD data[0] (should load 2 into REG)");
  send_packet(0, INSTR_RUNPROG, false, true);
  delay(10);
  print_cpu_state(); // Should show PC=1, REG=2
  
  // Execute instruction at PC=1 (ADD 3)
  Serial.println("\n  Executing: ADD data[1] (should add 3 to REG)");
  send_packet(0, INSTR_RUNPROG, false, true);
  delay(10);
  print_cpu_state(); // Should show PC=2, REG=5
  
  Serial.println("\n=== Test Complete! ===");
  Serial.println("Expected: PC=2, REG=5");
}
