import Foundation

final class Client {
    let identifier: String
    let hostname: String
    let connectionTime: Int
    var nickname: String?
    var username: String?
    var realname = ""
    var invisible = false
    var registered = false
    var registrationTime: Int?
    var lastReceived: Int
    var lastSpeaking = 0
    var pingSent: Int?
    var tokens: Int
    var refillTime: Int?
    var queue: [String] = []
    var channels: [Channel] = []
    var invites: [Channel] = []
    var away = ""
    var received = 0
    var sent = 0
    var active = true

    init(_ identifier: String, hostname: String, time: Int, capacity: Int) {
        self.identifier = identifier
        self.hostname = hostname
        connectionTime = time
        lastReceived = time
        tokens = capacity
    }

    var addressee: String { nickname ?? "*" }
    var prefix: String { "\(nickname!)!\(username!)@\(hostname)" }
    var mode: String { invisible ? "+i" : "+" }

    func useToken(time: Int, capacity: Int, interval: Int) {
        if tokens == capacity { refillTime = time + interval }
        tokens -= 1
    }

    func refill(time: Int, capacity: Int, interval: Int) {
        if refillTime == time {
            tokens += 1
            refillTime = tokens < capacity ? time + interval : nil
        }
    }
}
