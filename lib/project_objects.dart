// ignore_for_file: constant_identifier_names

import 'package:firebase/firebase.dart';
import 'package:intl/intl.dart';
import 'package:quiver/core.dart';
import 'package:pdf/widgets.dart' as pw;

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
    if(details["memo"] != null && details["memo"].toString().contains("Head of Household ID")) {
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
    else if(details["memo"].toString().contains("Order Info")){
      List<String> orderInfo = details["memo"].toString().split("Order Info: ").last.split(", ");
      hoh = FamilyMember("T-Shirts (${orderInfo[1]})", orderInfo[2], Location("", ""), DateTime.now());
    }

    double amt = double.parse(object["amount"]["value"]); 

    Invoice ret = Invoice(id, invNum, status, startedDate, viewed, hoh, amt, url);
    // ret.items = items;
    return ret; 

  }

}

class InvoiceItems{

  TshirtOrder shirtsOrder = TshirtOrder();

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
    for (var size in shirtsOrder.quantities.keys) { 
      // if(size == null) {
      //   continue;
      // }

      Map<String, Object> temp = {};

      String sizeName = size.name.split('_').join(' ');

      temp['name'] = "T-Shirt Order Form Purchase";
      temp['quantity'] = shirtsOrder.quantities[size] as Object;
      temp['description'] = "T-Shirt Size: $sizeName x ${temp['quantity']}";
      
      int cost;
      switch (size) {
        case TshirtSize.Youth_XS:
        case TshirtSize.Youth_XL:
        case TshirtSize.Youth_S:
        case TshirtSize.Youth_M:
        case TshirtSize.Youth_L:
          cost = 10;
          break;
        default:
          cost = 15;
          break;
      }

      temp["unit_amount"] = {
        "currency_code": "USD",
        "value": cost.toStringAsFixed(2)
      };

      ret.add(temp);

    }
    
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

class Report {

  int adults = 0;
  int children = 0;
  int babies = 0;
  double assessmentAmtTotal = 0;
  double assessmentAmtpaid = 0;
  double numPayments = 0;

  TshirtOrder shirts = TshirtOrder();
  double shirtOrders = 0;
  double shirtOrdersAmtTotal = 0;
  double shirtOrdersAmtPaid = 0;

  var pdf = pw.Document();  

  Report();

  void addInvoice(Invoice inv) {
    bool utaInvoice = false;
    if (inv.items.shirtsOrder.getShirts().isNotEmpty) {
      for (var shirt in inv.items.shirtsOrder.getShirts()) {
        shirts.addShirt(shirt);
      }
      shirtOrders++;
      shirtOrdersAmtTotal += inv.items.shirtsOrder.getTotal();
      shirtOrdersAmtPaid += inv.paid;
    }
    else {
      for (var member in inv.items.tickets) {
        if (!member!.UTA) {
          switch (member.tier) {
            case FamilyMemberTier.Adult:
              adults++;
              break;
            case FamilyMemberTier.Child:
              children++;
              break;
            case FamilyMemberTier.Baby:
              babies++;
              break;
            default:
          }
        }
        else {
          utaInvoice = true;
        }
      }
      if(!utaInvoice) {
        assessmentAmtTotal += inv.amt;
        assessmentAmtpaid += inv.paid;
        numPayments += inv.payments.length;
      }
    }    
  }

  pw.Document getPdf() {
    
    final currencyFormat = NumberFormat("#,##0.00", "en_US");

    var page = pw.Page(
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text("KC Teague Family Reunion 2022", style: pw.Theme.of(context).header3),
          pw.Text("Financial Report: ${DateFormat('MMM d, yyyy').format(DateTime.now())}", style: pw.Theme.of(context).header4, textAlign: pw.TextAlign.left),
          pw.Text("\n"), pw.Text("\n"), pw.Text("\n"),
          pw.Text("Registrations", style: pw.Theme.of(context).header4.copyWith(decoration: pw.TextDecoration.underline), textAlign: pw.TextAlign.left), pw.Text("\n"),
          pw.Text("Adults: $adults", style: pw.Theme.of(context).header5, textAlign: pw.TextAlign.left), pw.Text("\n"),
          pw.Text("Children: $children", style: pw.Theme.of(context).header5, textAlign: pw.TextAlign.left), pw.Text("\n"),
          pw.Text("Babies: $babies", style: pw.Theme.of(context).header5, textAlign: pw.TextAlign.left), pw.Text("\n"),
          pw.Text("Assessments Amount Owed: \$${currencyFormat.format(assessmentAmtTotal)}", style: pw.Theme.of(context).header5, textAlign: pw.TextAlign.left), pw.Text("\n"),
          pw.Text("Assessments Amount Paid: \$${currencyFormat.format(assessmentAmtpaid)}", style: pw.Theme.of(context).header5, textAlign: pw.TextAlign.left), pw.Text("\n"),
          pw.Text("# of Payments: $numPayments", style: pw.Theme.of(context).header5, textAlign: pw.TextAlign.left),
          pw.Text("\n"), pw.Text("\n"),
          pw.Text("T-Shirt Orders", style: pw.Theme.of(context).header4.copyWith(decoration: pw.TextDecoration.underline), textAlign: pw.TextAlign.left), pw.Text("\n"),
          pw.Text("# of Orders: $shirtOrders", style: pw.Theme.of(context).header5, textAlign: pw.TextAlign.left), pw.Text("\n"),
          pw.Text("# of Shirts: ${shirts.getShirts().length}", style: pw.Theme.of(context).header5, textAlign: pw.TextAlign.left), pw.Text("\n"),
          pw.Text("\n"),
          pw.Text("Smalls: ${shirts.quantities[TshirtSize.S]}", style: pw.Theme.of(context).header5, textAlign: pw.TextAlign.left), pw.Text("\n"),
          pw.Text("Mediums: ${shirts.quantities[TshirtSize.M]}", style: pw.Theme.of(context).header5, textAlign: pw.TextAlign.left), pw.Text("\n"),
          pw.Text("Larges: ${shirts.quantities[TshirtSize.L]}", style: pw.Theme.of(context).header5, textAlign: pw.TextAlign.left), pw.Text("\n"),
          pw.Text("XL's: ${shirts.quantities[TshirtSize.XL]}", style: pw.Theme.of(context).header5, textAlign: pw.TextAlign.left), pw.Text("\n"),
          pw.Text("2X's: ${shirts.quantities[TshirtSize.XXL]}", style: pw.Theme.of(context).header5, textAlign: pw.TextAlign.left), pw.Text("\n"),
          pw.Text("3X's: ${shirts.quantities[TshirtSize.XXL]}", style: pw.Theme.of(context).header5, textAlign: pw.TextAlign.left), pw.Text("\n"),
          pw.Text("4X's: ${shirts.quantities[TshirtSize.S]}", style: pw.Theme.of(context).header5, textAlign: pw.TextAlign.left), pw.Text("\n"),
          pw.Text("Youth XS's: ${shirts.quantities[TshirtSize.Youth_XS]}", style: pw.Theme.of(context).header5, textAlign: pw.TextAlign.left), pw.Text("\n"),
          pw.Text("Youth Smalls: ${shirts.quantities[TshirtSize.Youth_S]}", style: pw.Theme.of(context).header5, textAlign: pw.TextAlign.left), pw.Text("\n"),
          pw.Text("Youth Mediums: ${shirts.quantities[TshirtSize.Youth_M]}", style: pw.Theme.of(context).header5, textAlign: pw.TextAlign.left), pw.Text("\n"),
          pw.Text("Youth Larges: ${shirts.quantities[TshirtSize.Youth_L]}", style: pw.Theme.of(context).header5, textAlign: pw.TextAlign.left), pw.Text("\n"),
          pw.Text("Youth XL's: ${shirts.quantities[TshirtSize.Youth_XL]}", style: pw.Theme.of(context).header5, textAlign: pw.TextAlign.left), pw.Text("\n"),
          pw.Text("\n"),
          pw.Text("Orders Amount Owed: \$${currencyFormat.format(shirtOrdersAmtTotal)}", style: pw.Theme.of(context).header5, textAlign: pw.TextAlign.left), pw.Text("\n"),
          pw.Text("Orders Amount Paid: \$${currencyFormat.format(shirtOrdersAmtPaid)}", style: pw.Theme.of(context).header5, textAlign: pw.TextAlign.left), pw.Text("\n"),
        ]
      ),
    );

    pdf.addPage(page);
    
    return pdf;

  }  

}

class TshirtDelivery {

  bool needDelivery = true;

  String address = "";


}

class TshirtOrder {

  late String id;

  TshirtDelivery delivery = TshirtDelivery();
  Map<TshirtSize, int> quantities = {};
  final List<TshirtSize> _shirts = [];

  String orderName = "";
  String orderNumber = "";
  String orderEmail = "";

  TshirtOrder() {
    id = DateTime.now().millisecondsSinceEpoch.toString();
  }

  void addShirt(TshirtSize shirt) {

    _shirts.add(shirt);

    int x = 0;
    for (var _shirt in _shirts) { 
      if (shirt == _shirt) {
        x++;
      }
    }

    quantities[shirt] = x;

  }

  void removeShirt(TshirtSize shirt) {

    _shirts.remove(shirt);

    int x = 0;
    for (var _shirt in _shirts) { 
      if (shirt == _shirt) {
        x++;
      }
    }

    quantities[shirt] = x;

  }

  double getTotal() {

    double total = 0;
    for (TshirtSize shirt in _shirts) {
      
      // if(shirt==null) {
      //   continue;
      // }
      
      switch (shirt) {
        case TshirtSize.Youth_XS:
        case TshirtSize.Youth_XL:
        case TshirtSize.Youth_S:
        case TshirtSize.Youth_M:
        case TshirtSize.Youth_L:
          total += 10;
          break;
        default:
          total += 15;
          break;
      }

    }

    return total;

  }

  List<TshirtSize> getShirts() {
    return _shirts;
  }

}

class Verification {

  String verifiedId;
  String email;

  Verification(this.verifiedId, this.email);

}