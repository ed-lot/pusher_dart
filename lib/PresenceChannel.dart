import 'dart:convert';

import 'package:pusher_dart/Channel.dart';
import 'package:pusher_dart/Connection.dart';

class PresenceChannel extends Channel {
  late Members members;

  PresenceChannel(String name, Connection connection, [String? data]) : super(name, connection, data);

  Future<bool> connect() async {
    this.members = Members();
    String? auth;
    String? channel_data;
    try {
      var data = await super.connection.authenticate(name);
      if (data.containsKey("auth")) auth = data["auth"];
      if (data.containsKey("channel_data")) {
        channel_data = data["channel_data"];
        members.setMyID(jsonDecode(channel_data!)["user_id"]);
      }
    } catch (e) {
      print("Error: ${e.toString()}");
    }
    return trigger('pusher:subscribe', {'channel': name, 'auth': auth, 'channel_data': super.data ?? channel_data});
  }

  handleChannelMessage(Map<String, dynamic> message) {
    String eventName = message["event"] as String;
    if (eventName.startsWith("pusher_internal:")) {
      this._handleInternalEvent(message);
    } else {
      this.broadcast(message['event'] as String, message['data']);
    }
  }

  _handleInternalEvent(Map<String, dynamic> message) {
    var eventName = message["event"];
    var data = jsonDecode(message['data'] as String);
    switch (eventName) {
      case 'pusher_internal:subscription_succeeded':
        this.members.onSubscription(data);
        this.broadcast('pusher:subscription_succeeded', this.members);
        break;
      case 'pusher_internal:member_added':
        Member member = this.members.addMember(data);
        this.broadcast('pusher:member_added', member);
        break;
      case 'pusher_internal:member_removed':
        Member member = this.members.removeMember(data);
        this.broadcast('pusher:member_removed', member);
        break;
    }
  }
}

/** Represents a collection of members of a presence channel. */
class Members {
  List<Member> members = [];
  int count = 0;
  int? myID;
  Member? me;

  Members();

  /** Handles subscription data. For internal use only. */
  onSubscription(subscriptionData) {
    Map<String, dynamic> hash = subscriptionData["presence"]["hash"];
    hash.forEach((key, value) {
      this.members.add(Member(int.parse(key), value as Map<String, dynamic>));
    });
    this.count = this.members.length;
    this.me = members.firstWhere((member) {
      return member.id == this.myID;
    });
  }

  /** Adds a new member to the collection. For internal use only. */
  addMember(memberData) {
    bool exist = this.members.contains((member) {
      return member.id == memberData["user_id"];
    });
    if (!exist) {
      this.count++;
      Member m = Member(memberData["user_id"], memberData["user_info"]);
      this.members.add(m);
      return m;
    } else {
      Member m = this.members.firstWhere((member) {
        return member.id == memberData["user_id"];
      });
      m.info = memberData["user_info"];
      return m;
    }
  }

  /** Adds a member from the collection. For internal use only. */
  removeMember(memberData) {
    int index = this.members.indexWhere((member) {
      return member.id == memberData["user_id"];
    });
    if (index != null) {
      Member member = this.members.removeAt(index);
      this.count--;
      return member;
    }
    return null;
  }

  /** Updates the id for connected member. For internal use only. */
  setMyID(int id) {
    this.myID = id;
  }
}

/** Represents member of a presence channel. */
class Member {
  int id;
  Map<String, dynamic> info;

  Member(this.id, this.info);
}
