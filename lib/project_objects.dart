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
  // ignore: constant_identifier_names
  Riverwalk, Alamo, SixFlags, SeaWorld,
  // ignore: constant_identifier_names
  Caverns, Zoo, Bus, Shopping, Ripleys, 
  // ignore: constant_identifier_names
  Splashtown, Escape, Aquatica
}

enum InvoiceStatus {
  complete, sent, inProgress, cancelled, other
}

enum FamilyMemberTier {
  Adult, Child, Baby
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

class AssessmentStatus {

  bool created = false;
  late String invoiceId;
  late Invoice invoice;

  static Map<String, dynamic> toMap(AssessmentStatus assessmentStatus) {

    Map<String, dynamic> object = {};
    
    object['created'] = assessmentStatus.created;

    if(assessmentStatus.created) {
      object['invoiceId'] = assessmentStatus.invoiceId;
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
    }

    return ret; 

  }

}

class Location {

  String state;
  String city;

  Location(this.state, this.city);

  String displayInfo() => state + ", " + city;

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
        status = InvoiceStatus.inProgress;
        break;
      case "SENT":
        status = InvoiceStatus.sent;
        break;
      case "MARKED_AS_PAID":
      case "PAID":
        status = InvoiceStatus.complete;
        break;
      case "CANCELLED":
        status = InvoiceStatus.cancelled;
        break;
      default:
        status = InvoiceStatus.other;
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
          hoh = FamilyMember.toMember(query.snapshot.val());
          hoh!.id = query.snapshot.key;
        }
      });
    }


    double amt = double.parse(object["amount"]["value"]); 

    Invoice ret = Invoice(id, invNum, status, startedDate, viewed, hoh, amt, url);
    // ret.items = items;
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

    tickets.forEach((theMember) {

      Map<String, Object> temp = {}; 

      temp["name"] = theMember!.tier.toString().split('.').last + " Assessment";
      String item = theMember.tier == FamilyMemberTier.Baby ? "Tshirt Purchase" : "Assessment";
      temp["description"] = "KC Teague 2022 $item for: ${theMember.name}";
      temp["quantity"] = "1";
      temp["unit_amount"] = {
        "currency_code": "USD",
        "value": (theMember.tier == FamilyMemberTier.Adult ? 100.00 : 25.00).toStringAsFixed(2)
      };

      ret.add(temp);

    });

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
      var toAdd;
      switch (member!.tier) {
        case FamilyMemberTier.Adult:
          toAdd = 100;
          break;
        case FamilyMemberTier.Child:
          toAdd = 25;
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
  TshirtSize? tSize;

  bool registered = false;

  FamilyMember(this.name, this.email, this.location, this.dob) {
    age = Age.dateDifference(fromDate: dob, toDate: DateTime.now());
    tier = age.years > 11 ? FamilyMemberTier.Adult : FamilyMemberTier.Child; 
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

    if(member.tSize != null) {
      object["tSize"] = member.tSize.toString().split('.')[1].split('_').join(" ");
    }

    return object;

  }

  static FamilyMember toMember(Map<String, dynamic> object) {

    String name = object['name'];
    String email = object['email'];
    Location location = Location(
      object['location']['state'],
      object['location']['city']
    );
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
    ret.assessmentStatus = assessmentStatus;
    ret.addPhone(phone);

    return ret; 

  }

}
