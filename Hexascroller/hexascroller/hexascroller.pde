
// CLOCK PIN: A0 (22)
// DATA 1: A1 (23)
// DATA 2: A2 (24)
// DATA 3: A3 (25)
// CLOCK PIN: A4 (26)
// CLOCK PIN: A5 (27)

// ROW 0: E4 (2)
// ROW 1: E5 (3)
// ROW 2: E3 (5)
// ROW 3: H3 (6)
// ROW 4: H4 (7)
// ROW 5: H5 (8)
// ROW 6: H6 (9)

// PIEZO: L3 (46) (T5A)

//#define GREETING "Now with lowercase http://wiki.nycresistor.com/wiki/hexascroller"
#define GREETING "!s command to set default message"

const static int columns = 120;
const static int modules = 3;
const static int rows = 7;

static int active_row = -1;

#include <avr/pgmspace.h>
#include "hfont.h"
#include <EEPROM.h>

typedef enum {
  LEFT,
  RIGHT,
  UP,
  DOWN,
  NONE
} Direction;

Direction dir = LEFT;
int scroll_delay = 31;

// Resources:
// 256K program space
// 8K RAM
uint8_t b1[columns*modules];
uint8_t b2[columns*modules];
uint8_t rowbuf[columns];

class Bitmap {
  uint8_t* data;
  uint8_t* dpl;
public:
  Bitmap() {
    data = b1;
    dpl = b2;
  }
  void erase() {
    for (int i = 0; i < columns*modules; i++) data[i] = 0;
  }
  void writeStr(char* p, int x, int y) {
    while (*p != '\0') {
      x = writeChar(*p,x,y);
      p++;
      x++;
    }
  }

  int writeChar(char c, int x, int y, bool wrap = true) {
    int coff = (int)c * 8;
    uint8_t row = pgm_read_byte(charData+coff);
    if (c == ' ') return x+2;
    if (row == 0) {
      return x;
    }
    uint8_t mask = 0xfe >> y;
    while (row != 1) {
      row = row >> y;
      if (wrap) {
        x = x % (columns*modules);
        if (x < 0) { x = x + columns*modules; }
      }
      if (x >= 0 && x < columns*modules) {
        data[x] = row | (data[x] & mask);
      }
      coff++;
      x++;
      row = pgm_read_byte(charData+coff);
    }
    return x;
  }
  void flip() {
    cli();
    uint8_t* tmp = data;
    data = dpl;
    dpl = tmp;
    sei();
  }
  
  uint8_t* buildRowBuf(int row) {
    uint8_t* p = getDisplay();
    uint8_t mask = 1 << (7-row);
    for (int i = 0; i < columns; i++) {
      rowbuf[i] = 0;
      if ( (p[i] & mask) != 0 ) {
        rowbuf[i] |= 1<<1;
      }
      if ( (p[i+columns] & mask) != 0 ) {
        rowbuf[i] |= 1<<2;
      }
      if ( (p[i+(2*columns)] & mask) != 0 ) {
        rowbuf[i] |= 1<<3;
      }
    }
    return rowbuf;
  }
  
  uint8_t* getDisplay() { return dpl; }
};

int buzz_len = 0;

void buzz() {
  if (buzz_len > 0) {
    buzz_len--;
    if (buzz_len == 0) {
      TCCR5A = 0;
      TCCR5B = 0;
    }
  }
}

void startBuzz(int frequency, int length) {
  DDRL |= 1 << 3;
  // mode 4, CTC, clock src = 1/8
  TCCR5A = 0b01000000;
  TCCR5B = 0b00001010;
  // period = 1/freq 
  int period = 2000000 / frequency;
  OCR5A = period; // 3000; // ~500hz
  if (length <= 0) { buzz_len = 1; }
  else { buzz_len = length; }
}

static Bitmap b;

inline void rowOff() {
  PORTE &= ~(_BV(4) | _BV(5) | _BV(3));
  PORTH &= ~(_BV(3) | _BV(4) | _BV(5) | _BV(6));
}

inline void rowOn(int row) {
  // ROW 0: E4 (2)
  // ROW 1: E5 (3)
  // ROW 2: E3 (5)
  // ROW 3: H3 (6)
  // ROW 4: H4 (7)
  // ROW 5: H5 (8)
  // ROW 6: H6 (9)
  switch( row ) {
    case 6: PORTE |= _BV(4); break;
    case 5: PORTE |= _BV(5); break;
    case 4: PORTE |= _BV(3); break;
    case 3: PORTH |= _BV(3); break;
    case 2: PORTH |= _BV(4); break;
    case 1: PORTH |= _BV(5); break;
    case 0: PORTH |= _BV(6); break;
  }
}

void setup() {
  b.erase();
  b.flip();
  b.erase();
  //b.flip();
  // CLOCK PIN: A0
  // DATA 1: A1
  // DATA 2: A2
  // DATA 3: A3
  DDRA = 0x3f;
  PORTA = 0x3f;
// ROW 0: E4 (2)
// ROW 1: E5 (4)
// ROW 2: E3 (5)
// ROW 3: H3 (6)
// ROW 4: H4 (7)
// ROW 5: H5 (8)
// ROW 6: H6 (9)
  DDRE |= _BV(4) | _BV(5) | _BV(3);
  DDRH |= _BV(3) | _BV(4) | _BV(5) | _BV(6);
  PORTE &= ~(_BV(4) | _BV(5) | _BV(3));
  PORTH &= ~(_BV(3) | _BV(4) | _BV(5) | _BV(6));
  // 2ms per row/interrupt
  // clock: 16MHz
  // target: 500Hz
  // 32000 cycles per interrupt
  // Prescaler: 1/64 OC: 500
  // CS[2:0] = 0b011
  // WGM[3:0] = 0b0100 CTC mode (top is OCR3A)
  
  TCCR3A = 0b00000000;
  TCCR3B = 0b00001011;
  TIMSK3 = _BV(OCIE3A);
  OCR3A = 300;

  Serial.begin(9600);
  Serial.println("Okey-doke, here we go.");

  // Set up xbee
  Serial2.begin(9600);
  delay(1100);
  Serial2.print("+++");
  delay(1100);
  Serial2.flush();
  Serial2.print("ATPL2\r");
  delay(90);
  Serial2.flush();
  Serial2.print("ATMY1\r");
  delay(90);
  Serial2.flush();
  Serial2.print("ATDL2\r");
  delay(90);
  Serial2.flush();
  Serial2.print("ATSM0\r");
  delay(90);
  Serial2.flush();
  Serial2.print("ATCN\r");
  delay(1100);

  Serial2.flush();
  Serial.println("XBEE up.");

  delay(100);
}

static unsigned int curRow = 0;

#define CMD_SIZE 200
#define MESSAGE_TICKS (modules*columns*20)
static int message_timeout = 0;
static char message[CMD_SIZE+1];
static char command[CMD_SIZE+1];
static int cmdIdx = 0;

const static uint16_t DEFAULT_MSG_OFF = 0x10;

int eatInt(char*& p) {
  int v = 0;
  while (*p >= '0' && *p <= '9') {
    v *= 10;
    v += *p - '0';
    p++;
  }
  return v;
}

void processCommand() {
  if (command[0] == '!') {
    // command processing
    switch (command[1]) {
    case 's':
      // Set default string
      for (int i = 2; i < CMD_SIZE+1; i++) {
	EEPROM.write(DEFAULT_MSG_OFF-2+i,command[i]);
	if (command[i] == '\0') break;
      }
      Serial2.println("OK");
      break;
    case 'S':
      // Get current scroller status
      Serial2.print("MSG:");
      Serial2.println(message);
      break;
    case 'b':
      {
        char* p = command + 2;
        int freq = eatInt(p);
        if (*p != '\0') {
          p++;
        }
        int period = eatInt(p);
        if (freq == 0) { freq = 500; }
        if (period == 0) { period = 5; }
        startBuzz(freq,period);
      }        
      Serial2.println("OK");
      break;
    case 'd':
      switch (command[2]) {
      case 'l': dir = LEFT; break;
      case 'r': dir = RIGHT; break;
      case 'u': dir = UP; break;
      case 'd': dir = DOWN; break;
      case 'n': dir = NONE; break;
      default:
	Serial2.println("Unrecognized direction");
	return;
	break;
      }
      Serial2.println("OK");
      break;
    }	
  } else {
    // message
    message_timeout = MESSAGE_TICKS;
    for (int i = 0; i < CMD_SIZE+1; i++) {
      message[i] = command[i];
      if (command[i] == '\0') break;
    }
  }
}

static int xoff = 0;
static int yoff = 0;

void loop() {
  delay(scroll_delay);
  buzz();
  b.erase();
  if (message_timeout == 0) {
    // read message from eeprom
    uint8_t c = EEPROM.read(DEFAULT_MSG_OFF);
    if (c == 0xff) {
      // Fallback if none written
      b.writeStr(GREETING,xoff,yoff);
    } else {
      int idx = 0;
      while (idx < CMD_SIZE && c != '\0' && c != 0xff) {
	message[idx++] = c;
        c = EEPROM.read(DEFAULT_MSG_OFF+idx);
      }
      message[idx] = '\0';
      b.writeStr(message,xoff,yoff);
    }
  } else {
    b.writeStr(message,xoff,yoff);
    message_timeout--;
  }
  switch (dir) {
  case LEFT: xoff--; break;
  case RIGHT: xoff++; break;
  case UP: yoff--; break;
  case DOWN: yoff++; break;
  }

  if (xoff < 0) { xoff += modules*columns; }
  if (xoff >= modules*columns) { xoff -= modules*columns; }
  if (yoff < 0) { yoff += 7; }
  if (yoff >= 7) { yoff -= 7; }

  b.flip();
  int nextChar = Serial2.read();
  while (nextChar != -1) {
    if (nextChar == '\n') {
      command[cmdIdx] = '\0';
      processCommand();
      cmdIdx = 0;
      nextChar = -1;
    } else {
      command[cmdIdx] = nextChar;
      cmdIdx++;
      if (cmdIdx > CMD_SIZE) cmdIdx = CMD_SIZE;
      nextChar = Serial2.read();
    }
  }
}

#define CLOCK_BITS (1<<0 | 1<<4 | 1<<5)

ISR(TIMER3_COMPA_vect)
{
  uint8_t row = curRow % 7;
  //  uint8_t mask = 1 << (7-row);
  //uint8_t* p = b.getDisplay();
  uint8_t* p = b.buildRowBuf(row);
  rowOff();
  for (int i = 0; i < columns; i++) {
    __asm__("nop\n\t");
    __asm__("nop\n\t");
    __asm__("nop\n\t");
    __asm__("nop\n\t");
    PORTA = ~(p[i] | CLOCK_BITS);
    __asm__("nop\n\t");
    __asm__("nop\n\t");
    __asm__("nop\n\t");
    __asm__("nop\n\t");
    PORTA = ~(p[i] & ~CLOCK_BITS);
    __asm__("nop\n\t");
    __asm__("nop\n\t");
    __asm__("nop\n\t");
    __asm__("nop\n\t");
    PORTA = ~(p[i] | CLOCK_BITS);
  }
  rowOn(curRow%7);
  curRow++;
}

