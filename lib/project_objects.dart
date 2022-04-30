// ignore_for_file: constant_identifier_names

import 'package:firebase/firebase.dart';
import 'package:intl/intl.dart';
import 'package:quiver/core.dart';

enum TshirtSize { 
  Youth_XS, Youth_S, Youth_M, Youth_L, Youth_XL,
  S, M, L, XL, XXL, XXXL, XXXXL
}

enum TshirtColor {
  Orange, Blue, Grey
}

enum Activity {
  Riverwalk, Alamo, SixFlags, SeaWorld,
  Caverns, Zoo, Bus, Shopping, Ripleys, 
  Splashtown, Escape, Aquatica
}

enum InvoiceStatus {
  Paid, Sent, Paying, Cancelled, Other
}

enum FamilyMemberTier {
  Adult, Child, Baby
}

enum MemberSort {
  Alphabetical_Order, Reverse_Alphabetical_Order,
  Paid, Paying, Registered, Unregistered, UTA
}

class InvoiceLoadException implements Exception {
  String invNum;
  InvoiceLoadException(this.invNum);
}

class Age {

  late double years;
  late int months;
  late int days;

  static Age dateDifference(
    { required DateTime fromDate, required DateTime toDate}
  ) {
    Age age = Age();
    Duration diff = toDate.difference(fromDate);
    age.years = diff.inDays / 365;
    age.days = diff.inDays;
    age.months = diff.inDays ~/ 30;
    return age;
  }

}

enum AssessmentPosition {

  Hoh, Participant

}

class AssessmentStatus {

  bool created = false;
  late String invoiceId;
  late Invoice invoice;
  late AssessmentPosition position;

  static Map<String, dynamic> toMap(AssessmentStatus assessmentStatus) {

    Map<String, dynamic> object = {};
    
    object['created'] = assessmentStatus.created;

    if(assessmentStatus.created) {
      object['invoiceId'] = assessmentStatus.invoiceId;
      object['position'] = assessmentStatus.position.toString().split('.')[1];
    }

    return object;

  }

  static AssessmentStatus toAssessmentStatus(Map<String, dynamic> object) {

    bool created = object['created'];

    AssessmentStatus ret = AssessmentStatus();

    ret.created = created;
    if(created) {
      String invoiceId = object["invoiceId"];
      ret.invoiceId = invoiceId;
      ret.position = AssessmentPosition.values.firstWhere(
        (pos) {
          return pos.toString().toLowerCase() == "AssessmentPosition.".toLowerCase() + object['position'].toString().toLowerCase();
        }
      );
    }

    return ret; 

  }

}

class Invoice{

  String id;
  String invNum;
  InvoiceStatus status;
  DateTime startedDate;
  bool viewed;
  FamilyMember? hoh;
  double amt;
  double paid = 0;
  Uri url;
  InvoiceItems items = InvoiceItems();
  List<Payment> payments = [];

  Invoice(this.id, this.invNum, this.status, this.startedDate, this.viewed, this.hoh, this.amt, this.url);

  static Future<Invoice> toInvoice(Map<String, dynamic> object) async {

    Map<String, dynamic> details = object["detail"];

    String id = object['id'];
    String invNum = details["invoice_number"];
    Uri url = Uri.parse((object["links"] as List).firstWhere((element) => element["method"] == "GET")["href"].toString());
    InvoiceStatus status;
    switch (object["status"]) {
      case "PARTIALLY_PAID":
        status = InvoiceStatus.Paying;
        break;
      case "SENT":
        status = InvoiceStatus.Sent;
        break;
      case "MARKED_AS_PAID":
      case "PAID":
        status = InvoiceStatus.Paid;
        break;
      case "CANCELLED":
        status = InvoiceStatus.Cancelled;
        break;
      default:
        status = InvoiceStatus.Other;
    }

    DateTime startedDate = DateFormat("yyyy-MM-dd").parse(details["invoice_date"]);
    bool viewed = object["viewed_by_recipient"] == "true";

    FamilyMember? hoh;
    if(details["memo"] != null) {
      await database().ref("members").child(details["memo"].toString().split(': ').last).once('value')
      .then((query) {
        var val = query.snapshot.val();
        if(val == null) {
          hoh = null;
        }
        else {
          try {
            hoh = FamilyMember.toMember(query.snapshot.val());
            hoh!.id = query.snapshot.key;
          } on RangeError {
            throw InvoiceLoadException(invNum);
          }
        }
      });
    }

    double amt = double.parse(object["amount"]["value"]); 

    Invoice ret = Invoice(id, invNum, status, startedDate, viewed, hoh, amt, url);
    // ret.items = items;
    return ret; 

  }

}

class InvoiceItems{

  List<FamilyMember?> tickets = [];
  // Map<Activity, List<FamilyMember>> activities = {};
  // List<TShirtOrder> tshirts = [];

  void addMember(FamilyMember? member) {
    tickets.add(member);
  }

  // void addActivity(Activity activity, List<FamilyMember> members) {
  //   activities[activity] = members;
  // }

  void removeMember(FamilyMember member) {
    tickets.removeWhere((given) => given!.id == member.id);
  }

  List<Map<String, Object>> createItemList() {

    List<Map<String, Object>> ret = [];

    for (var theMember in tickets) {

      Map<String, Object> temp = {}; 

      temp["name"] = theMember!.tier == FamilyMemberTier.Baby ? "T-Shirt Purchase" : theMember.tier.toString().split('.').last + " Assessment";
      temp["description"] = "KC Teague 2022 ${temp["name"]} for: ${theMember.name}";
      temp["quantity"] = "1";
      temp["member"] = theMember;
      
      switch (theMember.tier) {
        case FamilyMemberTier.Baby:
          temp["unit_amount"] = {
            "currency_code": "USD",
            "value": 10.00
          };
          break;
        case FamilyMemberTier.Child:
          temp["unit_amount"] = {
            "currency_code": "USD",
            "value": 30.00
          };
          break;
        case FamilyMemberTier.Adult:
          temp["unit_amount"] = {
            "currency_code": "USD",
            "value": 100.00
          };
          break;
        default:
      }

      ret.add(temp);

    }

    // activities.forEach((activity, members) {
      
    //   ret["name"] = activity.toString().split(".").last;
    //   ret["description"] = "Group activity ticket";
    //   ret["quantity"] = "1";

    //   int amt;

    //   switch (activity) {
    //     case Activity.Riverwalk:
    //       amt = 14;
    //       break;
    //     case Activity.SixFlags:
    //       amt = 30;
    //       break;
    //     case Activity.SeaWorld:
    //       amt = 55;
    //       break;
    //     case Activity.Aquatica:
    //       amt = 40;
    //       break;
    //     case Activity.Splashtown:
    //       amt = ;
    //       break;
    //     default:
    //   }

    //   ret["unit_amount"] = 

    // })

    return ret;

  }

  double getTotal() {

    double total = 0;

    for (var member in tickets) {
      double toAdd = 0;
      switch (member!.tier) {
        case FamilyMemberTier.Adult:
          toAdd = 100;
          break;
        case FamilyMemberTier.Child:
          toAdd = 30;
          break;
        case FamilyMemberTier.Baby:
          toAdd = 10;
          break;
        default:
      }
      total += toAdd;
    }

    return total;

  }

  static Future<InvoiceItems> fromMap(List<Map<String, dynamic>> object) async {

    InvoiceItems items = InvoiceItems();

    for (var item in object) {

      switch (item["type"]) {
        case "member":
          FamilyMember? member;
          await database().ref("members").child(item["id"])
          .once('value').then((value) async => member = FamilyMember.toMember(value.snapshot.val())); 
          items.addMember(member);
          break;
        default:
      }

      // activities.forEach((activity, members) {
        
      //   ret["name"] = activity.toString().split(".").last;
      //   ret["description"] = "Group activity ticket";
      //   ret["quantity"] = "1";

      //   int amt;

      //   switch (activity) {
      //     case Activity.Riverwalk:
      //       amt = 14;
      //       break;
      //     case Activity.SixFlags:
      //       amt = 30;
      //       break;
      //     case Activity.SeaWorld:
      //       amt = 55;
      //       break;
      //     case Activity.Aquatica:
      //       amt = 40;
      //       break;
      //     case Activity.Splashtown:
      //       amt = ;
      //       break;
      //     default:
      //   }

      //   ret["unit_amount"] = 

      // })

    }

    return items;

  }

}

class FamilyMember{

  late String id;

  String name;
  String email;
  Location location;
  late String phone;
  DateTime dob;
  late Age age;
  late FamilyMemberTier tier;
  AssessmentStatus assessmentStatus = AssessmentStatus();
  Verification? verification;
  TshirtSize? tSize;
  // ignore: non_constant_identifier_names
  bool UTA = false;
  bool isDirectoryMember = true;

  FamilyMember(this.name, this.email, this.location, this.dob) {
    age = Age.dateDifference(fromDate: dob, toDate: DateTime.now());
    if(age.years > 11) {
      tier = FamilyMemberTier.Adult;
    }
    else if(age.years > 4) {
      tier = FamilyMemberTier.Child;
    }
    else {
      tier = FamilyMemberTier.Baby;
    }
  }

  FamilyMember addPhone(String givenPhone) { phone = givenPhone; return this; }

  String displayInfo() {

    String date = DateFormat('MM/dd/yyyy').format(dob);
    return "${name.split(' ').last}, ${name.split(' ').first}; $date";

  }

  String allInfo() {

    String date = DateFormat('MM/dd/yyyy').format(dob);
    return "${name.split(' ').last}, ${name.split(' ').first}; $email;${phone.isNotEmpty ? " $phone; " : null}${ location.city}, ${location.state}; $date";

  }

  @override
  int get hashCode => hash2(id.hashCode, name.hashCode);

  @override
  bool operator ==(Object other) {
    return (other is FamilyMember && other.id == id);
  }

  static Map<String, dynamic> toMap(FamilyMember member) {

    Map<String, dynamic> object = {};
    
    object['name'] = member.name;
    object['email'] = member.email;
    object['location'] = {
      'state': member.location.state, 
      'city': member.location.city
    };
    object['phone'] = member.phone;
    object['dob'] = member.dob.millisecondsSinceEpoch;
    object['assessmentStatus'] = AssessmentStatus.toMap(member.assessmentStatus);
    object['isDirectoryMember'] = member.isDirectoryMember;
    object['UTA'] = member.UTA;

    if(member.verification != null) {
      object['verification'] = { 
        "verifiedId": member.verification!.verifiedId, 
        "email": member.verification!.email
      };
    }

    if(member.tSize != null) {
      object["tSize"] = member.tSize.toString().split('.')[1].split('_').join(" ");
    }

    return object;

  }

  static FamilyMember toMember(Map<String, dynamic> object) {

    String name = object['name'];
    String email = object['email'];

    Location location = Location( object['location']['state'], object['location']['city'] ?? "");

    String phone = object['phone'];
    DateTime dob = DateTime.fromMillisecondsSinceEpoch(object['dob']);

    AssessmentStatus assessmentStatus = AssessmentStatus.toAssessmentStatus(object["assessmentStatus"]);

    FamilyMember ret = FamilyMember(name, email, location, dob);
    
    if(object.containsKey("tSize")) {
      TshirtSize size = TshirtSize.values.firstWhere(
        (e) {
          String temp = object['tSize'].toString();
          if(temp.contains(" ")) {
            temp = temp.split(' ').join("_");
          }
          return e.toString() == ("TshirtSize." + temp); 
        }
      );
      ret.tSize = size;
    }
    if(object.containsKey("verification")) {
      ret.verification = Verification(object['verification']['verifiedId'], object['verification']['email']);
    }
    if(object['isDirectoryMember'] == false) {
      ret.isDirectoryMember = false;
    }
    if(object['UTA'] == true) {
      ret.UTA = true;
    }
    ret.assessmentStatus = assessmentStatus;
    ret.addPhone(phone);

    return ret; 

  }

}

class Location {

  String state;
  String city;

  Location(this.state, this.city);

  String displayInfo() { 
    String ret = state;
    if(city.isNotEmpty) {
      ret += ", $city";
    }
    return ret;
  }

}

class Payment {

  String id;
  DateTime date;
  double amt;

  Payment(this.id, this.date, this.amt);

  static Payment fromMap(Map<String, dynamic> object) {

    String id = object["payment_id"];
    double amt = double.parse(object["amount"]["value"]);
    DateTime date = DateFormat("yyyy-MM-dd").parse(object["payment_date"]);

    return Payment(id, date, amt);

  }

}

class Verification {

  String verifiedId;
  String email;

  Verification(this.verifiedId, this.email);

}