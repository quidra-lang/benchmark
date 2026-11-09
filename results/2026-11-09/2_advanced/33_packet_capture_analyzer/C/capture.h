#ifndef CAPTURE_H
#define CAPTURE_H
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <setjmp.h>
#include <inttypes.h>
typedef int64_t Integer;
typedef enum { TYPE_INTEGER, TYPE_HEX2, TYPE_HEX4, TYPE_IPV4, TYPE_MAC, TYPE_STRING, TYPE_PRESENCE } Type;
typedef enum {
    F_FRAME_NUMBER,
    F_FRAME_TIME,
    F_FRAME_LEN,
    F_FRAME_PROTOCOLS,
    F_FRAME_MALFORMED,
    F_FRAME_BAD_CHECKSUM,
    F_ETH_DST,
    F_ETH_SRC,
    F_ETH_TYPE,
    F_ARP_OPCODE,
    F_ARP_SRC_HW,
    F_ARP_SRC_IP,
    F_ARP_DST_HW,
    F_ARP_DST_IP,
    F_IP_HDR_LEN,
    F_IP_TOS,
    F_IP_LEN,
    F_IP_ID,
    F_IP_FLAGS_DF,
    F_IP_FLAGS_MF,
    F_IP_FRAG_OFFSET,
    F_IP_TTL,
    F_IP_PROTO,
    F_IP_CHECKSUM,
    F_IP_CHECKSUM_STATUS,
    F_IP_SRC,
    F_IP_DST,
    F_IP_FRAGMENT,
    F_ICMP_TYPE,
    F_ICMP_CODE,
    F_ICMP_CHECKSUM,
    F_ICMP_CHECKSUM_STATUS,
    F_ICMP_ID,
    F_ICMP_SEQ,
    F_UDP_SRCPORT,
    F_UDP_DSTPORT,
    F_UDP_LENGTH,
    F_UDP_CHECKSUM,
    F_UDP_CHECKSUM_STATUS,
    F_TCP_SRCPORT,
    F_TCP_DSTPORT,
    F_TCP_STREAM,
    F_TCP_SEQ,
    F_TCP_SEQ_RAW,
    F_TCP_ACK,
    F_TCP_ACK_RAW,
    F_TCP_HDR_LEN,
    F_TCP_FLAGS,
    F_TCP_FLAGS_FIN,
    F_TCP_FLAGS_SYN,
    F_TCP_FLAGS_RST,
    F_TCP_FLAGS_PSH,
    F_TCP_FLAGS_ACK,
    F_TCP_FLAGS_URG,
    F_TCP_WINDOW,
    F_TCP_WINDOW_CALC,
    F_TCP_CHECKSUM,
    F_TCP_CHECKSUM_STATUS,
    F_TCP_URGENT,
    F_TCP_OPTION,
    F_TCP_OPTIONS_MSS,
    F_TCP_OPTIONS_WSCALE,
    F_TCP_OPTIONS_MALFORMED,
    F_TCP_LEN,
    F_TCP_ANALYSIS_RETRANSMISSION,
    F_TCP_ANALYSIS_OUT_OF_ORDER,
    F_TCP_ANALYSIS_LOST_SEGMENT,
    F_TCP_ANALYSIS_DUPLICATE_ACK,
    F_DNS_ID,
    F_DNS_FLAGS,
    F_DNS_FLAGS_RESPONSE,
    F_DNS_FLAGS_OPCODE,
    F_DNS_FLAGS_RCODE,
    F_DNS_COUNT_QUERIES,
    F_DNS_COUNT_ANSWERS,
    F_DNS_COUNT_AUTH_RR,
    F_DNS_COUNT_ADD_RR,
    F_DNS_QRY_NAME,
    F_DNS_QRY_TYPE,
    F_DNS_ANSWER,
    F_DNS_AUTHORITY,
    F_DNS_ADDITIONAL,
    F_DNS_A,
    F_DATA_LEN,
    F_ETH_ADDR,
    F_IP_ADDR,
    F_UDP_PORT,
    F_TCP_PORT,
    F_ETH,
    F_ARP,
    F_IP,
    F_ICMP,
    F_UDP,
    F_TCP,
    F_DNS,
    F_DATA,
    FIELD_COUNT
} Field;
#define STORED_FIELDS 84
struct FieldSpec {
    const char *name;
    Type type;
};
extern const struct FieldSpec field_specs[FIELD_COUNT];
typedef struct {
    unsigned char *data;
    size_t len;
} Bytes;
typedef struct {
    Integer number;
    char *text;
} Value;
typedef struct {
    Value *data;
    size_t len, cap;
} Values;
typedef struct {
    char **data;
    size_t len, cap;
} Lines;
typedef struct {
    char *data;
    size_t len, cap;
} Text;
typedef struct {
    Integer type;
    char *body;
} Answer;
typedef struct {
    Integer number, time, length;
    Bytes raw, remaining;
    char *reason;
    int layers[8], layer_count;
    Values fields[STORED_FIELDS];
    Answer *answers;
    size_t answer_count, answer_cap;
    Integer duplicate_origin, duplicate_count;
} Packet;
void *allocate(size_t count, size_t size);
void grow(void **data, size_t *cap, size_t need, size_t size);
char *format(const char *pattern, ...);
char *copy_string(const char *text);
char *part(const char *text, size_t size);
void text_add(Text *text, const char *pattern, ...);
void line_add(Lines *lines, const char *pattern, ...);
Lines read_lines(const char *path);
void write_lines(const char *name, Lines lines);
void pn(Packet *p, Field field, Integer value, bool append);
void ps(Packet *p, Field field, const char *value, bool append);
void flag(Packet *p, Field field);
bool has(const Packet *p, Field field);
Integer num(const Packet *p, Field field);
const char *str(const Packet *p, Field field);
void packet_error(Packet *p, const char *pattern, ...);
char *decimal(Integer value);
char *hexadecimal(Integer value, int width);
char *seconds(Integer value);
Integer read_integer(Bytes data, size_t position, size_t count);
Bytes slice(Bytes data, size_t first, size_t last);
const char *checksum(Bytes data);
char *mac(Integer value);
char *ipv4(Integer value);
Bytes ethernet(Packet *p, Bytes data);
void arp(Packet *p, Bytes data);
Bytes internet(Packet *p, Bytes data);
Bytes icmp(Packet *p, Bytes data);
Bytes udp(Packet *p, Bytes data);
Bytes tcp(Packet *p, Bytes data);
void dns(Packet *p, Bytes data);
char *type_name(Integer type);
char *rcode_name(Integer code);
Packet *read_capture(size_t *count);
Lines dump_lines(Bytes data);
typedef struct {
    Integer address, port;
} Endpoint;
typedef struct {
    Integer first, length;
} Interval;
typedef struct {
    Integer isn, mss, ws, base, expected, advanced, packets, payload;
    bool base_set, expected_set, previous_ack_set;
    Interval *intervals;
    size_t interval_count, interval_cap;
    Integer previous_ack[4], marks[4];
} Side;
typedef struct {
    Integer packet;
    int side, mark;
    Integer seq, length;
} Event;
typedef struct {
    const char *state;
    Integer packet;
} State;
typedef struct {
    Endpoint client, server;
    const char *state;
    State *history;
    size_t history_count, history_cap;
    Integer start, end, packets, bytes, f2, handshake[3];
    Side sides[2];
    Event *events;
    size_t event_count, event_cap;
    int first_close;
} Stream;
extern const char *mark_names[4];
void track(Packet *p, Stream *streams, size_t *stream_count);
typedef struct {
    int kind;
    Endpoint a, b;
    Integer first, start, end, packets[2], bytes[2];
} Conversation;
typedef struct {
    Integer address, packets[2], bytes[2];
} EndpointTotals;
Conversation *conversations(const Packet *packets, size_t count, size_t *result_count);
EndpointTotals *endpoints(const Packet *packets, size_t count, size_t *result_count);
char *endpoint(Endpoint value, bool port);
#endif
