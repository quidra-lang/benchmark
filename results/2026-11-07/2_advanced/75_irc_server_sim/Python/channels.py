from masks import matches


class Member:
    def __init__(self, client, operator=False):
        self.client = client
        self.operator = operator
        self.voice = False

    @property
    def status(self):
        return "@" if self.operator else "+" if self.voice else ""

    @property
    def display(self):
        return self.status + self.client.nickname


class Channel:
    def __init__(self, name, time):
        self.name = name
        self.created = time
        self.members = []
        self.topic = ""
        self.topic_setter = None
        self.topic_time = None
        self.bans = []
        self.flags = {"n", "t"}
        self.key = ""
        self.limit = 0
        self.peak = 0
        self.messages = 0

    def member(self, client):
        return next((member for member in self.members if member.client is client), None)

    def add(self, client, operator=False):
        member = Member(client, operator)
        self.members.append(member)
        client.channels.append(self)
        self.peak = max(self.peak, len(self.members))
        return member

    def remove(self, client):
        self.members.remove(self.member(client))
        client.channels.remove(self)

    def name_list(self, viewer):
        inside = self.member(viewer) is not None
        return " ".join(member.display for member in self.members if inside or not member.client.invisible)

    def banned(self, client):
        return any(matches(mask, client.prefix) for mask, setter, time in self.bans)

    def can_speak(self, client):
        member = self.member(client)
        privileged = member is not None and (member.operator or member.voice)
        return ((member is not None or "n" not in self.flags)
                and ("m" not in self.flags or privileged)
                and (privileged or not self.banned(client)))

    def mode_display(self, include_key=True):
        mode = "+"
        for character in "iklmnt":
            present = bool(self.key) if character == "k" else bool(self.limit) if character == "l" else character in self.flags
            if present:
                mode += character
        if include_key and self.key:
            mode += " " + self.key
        if self.limit:
            mode += " " + str(self.limit)
        return mode
