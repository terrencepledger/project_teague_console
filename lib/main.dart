import 'dart:convert';
import 'package:firebase/firebase.dart' as firebase;
import 'package:firebase/firebase.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart';
import 'package:intl/intl.dart';
import 'package:loader_overlay/loader_overlay.dart';
import 'package:project_teague_console/paypal.dart';
import 'package:project_teague_console/project_objects.dart';
import 'package:responsive_scaffold_nullsafe/responsive_scaffold.dart';
import 'package:collection/collection.dart';
import 'dart:typed_data';
import 'dart:html' as html;
import 'dart:js' as js;

void main() {
  if (firebase.apps.isEmpty) {
    firebase.initializeApp(
      apiKey: "AIzaSyBhlfX8XnrV7pWWt-aIvk9VPAboGmi-6nw",
      authDomain: "kcteaguesite.firebaseapp.com",
      databaseURL: "https://kcteaguesite-default-rtdb.firebaseio.com",
      projectId: "kcteaguesite",
      storageBucket: "kcteaguesite.appspot.com",
    );
  }else {
    firebase.app(); // if already initialized, use that one
  }
  runApp(const ConsoleApp());
}

class ConsoleApp extends StatelessWidget {
  const ConsoleApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KC Teague Console',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const LoaderOverlay(child: MyHomePage(title: 'HomePage')),
    );
  }
}

class MyHomePage extends StatefulWidget {

  const MyHomePage({Key? key, required this.title}) : super(key: key);

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();

}   

class _MyHomePageState extends State<MyHomePage> {

  DatabaseReference db = database().ref("members");
  late Report report;
  late Paypal paypal;

  MemberSort sorting = MemberSort.Alphabetical_Order;

  List<FamilyMember> members = [];
  List<Invoice> invoices = [];

  int assessmentCount = 0;
  int registered = 0;

  List<GlobalKey<FormState>> formKeys = [];
  Map<FamilyMember, DateTime> dobs = {};
  
  var sKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    context.loaderOverlay.show();
    paypal = Paypal(context);
    loadMembers();
    loadInvoices();
  }

  void checkRegisteredCount() {
    
    int temp = 0;
    for (var member in members) { 
      if(member.assessmentStatus.created) {
        Invoice? inv = invoices.firstWhereOrNull((inv) => inv.id == member.assessmentStatus.invoiceId);
        if(inv!=null) {
          switch (inv.status) {
            case InvoiceStatus.Paid:
            case InvoiceStatus.Paying:
              temp++;
              break;
            default:
              member.UTA ? null : temp++;
          }
        }
      }
    }

    setState(() {
      registered = temp;
    });

  }

  int checkTotalLikely() {
    return members.length - members.where((member) => member.UTA).length;
  }

  void loadMembers() {
    db.once('value').then((query) {
      List<FamilyMember> temp = [];
      Map<FamilyMember, DateTime> tempDobs = {};
      query.snapshot.forEach((child){
        setState(() {
          FamilyMember member = FamilyMember.toMember(child.val());
          member.id = child.key;
          temp.add(member);
          tempDobs[member] = member.dob;
          formKeys.add(GlobalKey<FormState>());
        });
      });
      setState(() {
        members = temp;
        dobs = tempDobs;
        sortMembers();
      });
    });
  }
   
  void sortInvoices() {
    //TODO: Implement sort for invoices based on paying, sent, complete
  }

  void sortMembers() {
    setState(() {
      members.sort(
        (a, b) {
          
          var aReversedName = a.name.split(' ').last + a.name.split(' ').first;
          var bReversedName = b.name.split(' ').last + b.name.split(' ').first;
          int compared = aReversedName.compareTo(bReversedName);

          switch (sorting) {
            case MemberSort.Registered:
              if(b.assessmentStatus.created & a.assessmentStatus.created) {
                return compared;
              }
              else if (b.assessmentStatus.created) {
                return 1;
              }
              return compared;
            case MemberSort.Unregistered:
              if(getTag(b) == "Unregistered" && getTag(a) == "Unregistered") {
                return compared;
              }
              else if (getTag(b) == "Unregistered") {
                return 1;
              }
              else if(getTag(a) == "Unregistered") {
                return -1;
              }
              return compared;
            case MemberSort.Reverse_Alphabetical_Order:
              return compared * -1;
            case MemberSort.UTA:
              if(getTag(b) == "U.T.A" && getTag(a) == "U.T.A") {
                return compared;
              }
              else if (getTag(b) == "U.T.A") {
                return 1;
              }
              else if(getTag(a) == "U.T.A") {
                return -1;
              }
              return compared;
            case MemberSort.Paying:
              if(getTag(b) == "Paying" && getTag(a) == "Paying") {
                return compared;
              }
              else if (getTag(b) == "Paying") {
                return 1;
              }
              else if(getTag(a) == "Paying") {
                return -1;
              }
              return compared;
            case MemberSort.Paid:
              if(getTag(b) == "Paid" && getTag(a) == "Paid") {
                return compared;
              }
              else if (getTag(b) == "Paid") {
                return 1;
              }
              else if(getTag(a) == "Paid") {
                return -1;
              }
              return compared;
            default:
              return compared;
          }
          
        }
      );
    });

  }

  void loadInvoices() {
    paypal.getInvoices(
      (List<Invoice> temp, Report givenReport, int givenCount) {
        setState(() {
          report = givenReport;
          invoices = temp;
          assessmentCount = givenCount;
        });
        context.loaderOverlay.hide();
        checkRegisteredCount();
      },
      (String code, String reason) {
        ScaffoldMessenger.of(context)
        .showSnackBar(
          SnackBar(
            content: Text("Unable to Load Invoices. Contact Terrence Pledger with code $code - $reason"),
            duration: const Duration(seconds: 8),
          )
        );
      }
    );
  }

  Future<void> selectDOB(int index) async { 
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: dobs[members.elementAt(index)] as DateTime,
      lastDate: DateTime.now(),
      firstDate: DateTime.fromMillisecondsSinceEpoch(-2208967200000)
    );
    DateTime now = DateTime.now();
    DateTime today = DateTime(now.year, now.month, now.day);
    if (picked != null && picked != today) {
      setState(() {
        dobs[members.elementAt(index)] = picked;
        members.elementAt(index).dob = picked;
      });
    }
  }

  Future<void> showReport() async {

    Uint8List pdfInBytes = await report.getPdf().save();
    final blob = html.Blob([pdfInBytes], 'application/pdf');
    final url = html.Url.createObjectUrlFromBlob(blob);

    js.context.callMethod('open', [url]);

  }

  String getTag(FamilyMember member) {

    if(member.assessmentStatus.created) {
      Invoice? inv = invoices.firstWhereOrNull((inv) => inv.id == member.assessmentStatus.invoiceId);
      if(inv!=null) {
        switch (inv.status) {
          case InvoiceStatus.Paid:
            return "Paid";
          case InvoiceStatus.Paying:
            return "Paying";
          default:
            return member.UTA ? "U.T.A" : "Registered";
        }
      }
    }

    return member.UTA ? "U.T.A" : "Unregistered";

  }

  @override
  Widget build(BuildContext context) {
    //FIXME: Navigation via member button tap from assessment is inconsistent
    // OH PROBABLY HAS TO DO WITH ORDER CHANGING DUE TO SORT! Maybe...
    return ThreeColumnNavigation(
      updateFunc: () {
        loadMembers();
        loadInvoices();
      },
      title: const Text('Navigation'),
      showDetailsArrows: true,
      backgroundColor: Colors.grey[100],
      sections: [
        MainSection(
          label: Text('Assessments $assessmentCount/${invoices.length}'),
          icon: const Icon(Icons.attach_money),
          itemCount: invoices.length,
          bottomAppBar: BottomAppBar(
            elevation: 1,
            color: Theme.of(context).primaryColor,
            child: Row(
              children: [
                //TODO: Add invoice sort dropdown 
                IconButton(
                  icon: const Icon(Icons.request_page_outlined),
                  onPressed: () {
                    Widget cancelButton = TextButton(
                      child: const Text("Cancel"),
                      onPressed:  () {
                        Navigator.of(context).pop();
                      },
                    );
                    Widget continueButton = TextButton(
                      child: const Text("Continue"),
                      onPressed:  () {
                        Navigator.of(context).pop();
                        showReport();
                      },
                    );
                    AlertDialog alert = AlertDialog(
                      title: const Text("Create Finance Report"),
                      content: const Text("Would you like to create a new finance report?"),
                      actions: [
                        cancelButton,
                        continueButton,
                      ],
                    );
                    // show the dialog
                    showDialog(
                      context: context,
                      builder: (BuildContext context) {
                        return alert;
                      },
                    );
                  },
                )
              ],
            ),
          ),
          itemBuilder: (context, index, selected) {
            if(index > invoices.length) {index = 0;}
            if(invoices.isEmpty) {
              return ListTile(
                leading: CircleAvatar(
                  child: Text(index.toString()),
                ),
                selected: selected,
                title: const Text(":("),
                subtitle: const Text('No Invoices'),
              );
            }
            return ListTile(
              leading: CircleAvatar(
                child: Text(index.toString()),
              ),
              selected: selected,
              title: Text("${invoices.elementAt(index).hoh?.name ?? "ERROR NO HOH"} - Inv#${invoices.elementAt(index).invNum}"),
              subtitle: Text(
                invoices.elementAt(index).status == InvoiceStatus.Paid ? "COMPLETE" : "IN PROGRESS"
              ),
            );
          },
          getDetails: (context, index, func) {
            if(invoices.isEmpty) {
              return DetailsWidget(
                title: const Text("Details"),
                child: Column(
                  // ignore: prefer_const_literals_to_create_immutables
                  children: [
                    const Expanded(
                      // ignore: unnecessary_const
                      child: const FittedBox(child: Text("No Invoices Yet\nGet Some Family Members Paying!",
                        textAlign: TextAlign.center,
                      )),
                    ),
                  ],
                ),
              );
            }
            return DetailsWidget(
              title: const Text('Details'),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.max,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Card(
                              color: Colors.lightBlueAccent,
                              shape: const RoundedRectangleBorder(
                                side: BorderSide(
                                  color: Colors.blue,
                                  width: 1
                                )
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Text(
                                  "Head of household: ${invoices.elementAt(index).hoh?.name ?? "ERROR NO HOH"}",
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Card(
                              color: Colors.lightBlueAccent,
                              shape: const RoundedRectangleBorder(
                                side: BorderSide(
                                  color: Colors.blue,
                                  width: 1
                                )
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Text(
                                  "Invoice Start Date: ${
                                  DateFormat("MM/dd/yyyy").format(invoices.elementAt(index).startedDate)
                                  }", 
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Card(
                              color: Colors.lightBlueAccent,
                              shape: const RoundedRectangleBorder(
                                side: BorderSide(
                                  color: Colors.blue,
                                  width: 1
                                )
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Text(
                                  "Viewed? - ${invoices.elementAt(index).viewed.toString()}", 
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Card(
                              color: Colors.lightBlueAccent,
                              shape: const RoundedRectangleBorder(
                                side: BorderSide(
                                  color: Colors.blue,
                                  width: 1
                                )
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Text(
                                  "Payment Status: \$${invoices.elementAt(index).paid}/\$${invoices.elementAt(index).amt.toString()}",
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Card(
                              color: Colors.lightBlueAccent,
                              shape: const RoundedRectangleBorder(
                                side: BorderSide(
                                  color: Colors.blue,
                                  width: 1
                                )
                              ),
                              child: Column(
                                children: [
                                  const Padding(
                                    padding: EdgeInsets.all(8.0),
                                    child: Text(
                                      "Item List:", 
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(10.0),
                                    child: Table(
                                      defaultColumnWidth: const IntrinsicColumnWidth(flex: 50),
                                      children: [ 
                                        const TableRow(
                                          children: [
                                            Center(child: Padding(
                                              padding: EdgeInsets.all(8.0),
                                              child: Text("Name", style: TextStyle(fontWeight: FontWeight.bold,)),
                                            )),  
                                            Center(child: Padding(
                                              padding: EdgeInsets.all(8.0),
                                              child: Text("Amount", style: TextStyle(fontWeight: FontWeight.bold,)),
                                            ))
                                          ]
                                        ),
                                        ...
                                        List.generate(invoices.elementAt(index).items.createItemList().length, 
                                          (memberIndex) => TableRow(
                                            children: [
                                              ElevatedButton(
                                                style: ElevatedButton.styleFrom(
                                                  primary: Colors.blue
                                                ),
                                                onPressed: () {
                                                  FamilyMember foundMember = invoices.elementAt(index).items.createItemList().elementAt(memberIndex)["member"] as FamilyMember; 
                                                  int foundMemberIndex = members.indexOf(foundMember);
                                                  func.call(1, foundMemberIndex);
                                                },
                                                child: Padding(
                                                  padding: const EdgeInsets.all(8.0),
                                                  child: Center(child: Text(
                                                    invoices.elementAt(index).items.createItemList().elementAt(memberIndex)["description"].toString().split("2022 ").last,
                                                    textAlign: TextAlign.center,
                                                    style: const TextStyle(color: Colors.black),
                                                  )),
                                                ),
                                              ),
                                              Padding(
                                                padding: const EdgeInsets.all(8.0),
                                                child: Center(child: Text(
                                                  "\$" + double.parse((invoices.elementAt(index).items.createItemList().elementAt(memberIndex)["unit_amount"] as Map)["value"].toString()).toStringAsFixed(2),
                                                  textAlign: TextAlign.center,
                                                  style: const TextStyle(color: Colors.black),
                                                )),
                                              ),
                                            ]
                                          )
                                        )
                                      ]
                                    )
                                  )
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Card(
                              color: Colors.lightBlueAccent,
                              shape: const RoundedRectangleBorder(
                                side: BorderSide(
                                  color: Colors.blue,
                                  width: 1
                                )
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Stack(
                                    alignment: AlignmentDirectional.center,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        // ignore: prefer_const_literals_to_create_immutables
                                        children: const [
                                          Expanded(
                                            child: Padding(
                                              padding: EdgeInsets.all(8.0),
                                              child: Text(
                                                "Payment List:", 
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: Padding(
                                          padding: const EdgeInsets.all(15.0),
                                          child: Tooltip(
                                            message: "Manual Entry",
                                            child: IconButton(
                                              icon: const Icon(
                                                Icons.add_circle_outline_rounded
                                              ),
                                              onPressed: () async {
                                                TextEditingController textController = TextEditingController();
                                                await showDialog(
                                                  context: context, 
                                                  builder: (context) {
                                                    return Dialog(
                                                      child: StatefulBuilder(
                                                        builder: (BuildContext context, setState2) {
                                                          return Padding(
                                                            padding: const EdgeInsets.all(8.0),
                                                            child: Container(
                                                              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width / 3),
                                                              child: Column(
                                                                mainAxisSize: MainAxisSize.min,
                                                                children:  [
                                                                  Padding(
                                                                    padding: const EdgeInsets.all(8.0),
                                                                    child: TextFormField(
                                                                      controller: textController,
                                                                      inputFormatters: <TextInputFormatter>[
                                                                        FilteringTextInputFormatter.allow(RegExp(r'^-{1}|(?=\D*(?:\d\D*){1,12}$)\d+(?:\.\d{0,4})?$')),
                                                                      ],
                                                                      // keyboardType: const TextInputType.numberWithOptions(signed: true),
                                                                      decoration: const InputDecoration(
                                                                        labelText: "Enter Payment Amount (negative allowed)"
                                                                      ),
                                                                    ),
                                                                  ),
                                                                  Padding(
                                                                    padding: const EdgeInsets.all(8.0),
                                                                    child: ElevatedButton.icon(
                                                                      onPressed: () async {
                                                                        double amt = double.parse(textController.text);
                                                                        Response res = await paypal.update(invoices.elementAt(index).url, amt);
                                                                        String msg;
                                                                        if(res.statusCode != 200) {
                                                                          msg = "Unable to enter payment: ${res.statusCode} - ${res.reasonPhrase}: ${json.decode(res.body)['details'][0]['description']}";
                                                                        }
                                                                        else {
                                                                          msg = "Successfully Entered";
                                                                        }
                                                                        ScaffoldMessenger.of(context).showSnackBar(
                                                                          SnackBar(
                                                                            content: Text(msg),
                                                                            duration: const Duration(seconds: 10),
                                                                          )
                                                                        );
                                                                        Navigator.of(context).pop();
                                                                        loadMembers();
                                                                        loadInvoices();
                                                                      }, 
                                                                      icon: const Icon(Icons.check),
                                                                      label: const Text("Submit")
                                                                    ),
                                                                  )
                                                                ],
                                                              ),
                                                            ),
                                                          );
                                                        },
                                                      ),
                                                    );
                                                  }
                                                );
                                              } 
                                            ),
                                          ),
                                        ),
                                      )
                                    ]
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(20.0),
                                    child: Table(
                                      defaultColumnWidth: const IntrinsicColumnWidth(flex: 50),
                                      children: [ 
                                        const TableRow(
                                          children: [
                                            Center(child: Padding(
                                              padding: EdgeInsets.all(8.0),
                                              child: Text("Payment ID", style: TextStyle(fontWeight: FontWeight.bold,)),
                                            )), 
                                            Center(child: Padding(
                                              padding: EdgeInsets.all(8.0),
                                              child: Text("Date", style: TextStyle(fontWeight: FontWeight.bold,)),
                                            )), 
                                            Center(child: Padding(
                                              padding: EdgeInsets.all(8.0),
                                              child: Text("Amount", style: TextStyle(fontWeight: FontWeight.bold,)),
                                            ))
                                          ]
                                        ),
                                        ...
                                        List.generate(invoices.elementAt(index).payments.length, 
                                          (index2) => TableRow(
                                            children: [
                                              Padding(
                                                padding: const EdgeInsets.all(8.0),
                                                child: Center(child: Text(invoices.elementAt(index).payments.elementAt(index2).id)),
                                              ),
                                              Padding(
                                                padding: const EdgeInsets.all(8.0),
                                                child: Center(child: Text(DateFormat("MM-dd-yyyy").format(
                                                  invoices.elementAt(index).payments.elementAt(index2).date
                                                ))),
                                              ),
                                              Padding(
                                                padding: const EdgeInsets.all(8.0),
                                                child: Center(child: Text("\$${invoices.elementAt(index).payments.elementAt(index2).amt.toStringAsFixed(2)}")),
                                              )
                                            ]
                                          )
                                        )
                                      ]
                                    ),
                                  )
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            paypal.sendReminder(context, invoices.elementAt(index), 
                              (String code, String reason) {
                                ScaffoldMessenger.of(context)
                                .showSnackBar(
                                  SnackBar(
                                    content: Text("Unable to Send Reminder. Contact Terrence Pledger with code $code - $reason"),
                                    duration: const Duration(seconds: 8),
                                  )
                                );
                              }
                            );
                          }, 
                          icon: const Icon(Icons.check),
                          label: const Text("Send Reminder")
                        ),
                      ),
                    )
                  ],
                ),
              ),
            );
          },
        ),
        MainSection(
          label: Text('Users $registered/${checkTotalLikely()}'),
          icon: const Icon(Icons.people),
          itemCount: members.length,
          itemBuilder: (context, index, selected) {
            if(index > members.length - 1) {index = 0;}
            return ListTile(
              leading: CircleAvatar(
                child: Text(members.elementAt(index).name[0]),
              ),
              selected: selected,
              title: Text(members.elementAt(index).name),
              subtitle: Text(
                getTag(members.elementAt(index))
              ),
            );
          },
          bottomAppBar: BottomAppBar(
            color: Theme.of(context).primaryColor,
            elevation: 1,
            child: Row(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.all(5.0),
                  child: DropdownButton<MemberSort>(
                    dropdownColor: Colors.blue,
                    value: sorting,
                    icon: const Icon(
                      Icons.filter_list,
                      color: Colors.white,
                    ),
                    onChanged: (newSortValue) {
                      setState(() {
                        if(newSortValue != null) {
                          sorting = newSortValue;
                        }
                        sortMembers();
                      });
                    },
                    items: MemberSort.values.map(
                      (sortValue) {
                        int count;
                        switch (sortValue) {
                          case MemberSort.Registered:
                            count = registered;
                            break;
                          case MemberSort.Unregistered:
                            count = members.fold(0, (previousValue, member) => getTag(member) == "Unregistered" ? ++previousValue : previousValue);
                            break;
                          case MemberSort.Paid:
                            count = members.fold(0, (previousValue, member) => getTag(member) == "Paid" ? ++previousValue : previousValue);
                            break;
                          case MemberSort.Paying:
                            count = members.fold(0, (previousValue, member) => getTag(member) == "Paying" ? ++previousValue : previousValue);
                            break;
                          case MemberSort.UTA:
                            count = members.fold(0, (previousValue, member) => getTag(member) == "U.T.A" ? ++previousValue : previousValue);
                            break;
                          case MemberSort.Reverse_Alphabetical_Order:
                          case MemberSort.Alphabetical_Order:
                          default:
                            count = members.length;
                        }

                        return DropdownMenuItem(
                          value: sortValue, 
                          child: Text(
                            "Sort by: " + sortValue.name.split('_').join(' ') + ": " + count.toString(),
                            style: const TextStyle(color: Colors.white), 
                          )
                        );
                      }
                    ).toList()
                  ),
                ),
              ],
            ),
          ),
          getDetails: (context, index, func) {
            if(index > members.length - 1) {index = 0;}
            return DetailsWidget(
              title: const Text('Details'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.info),
                  onPressed: () {
                    try {
                      Invoice? inv = invoices.firstWhere((invoice) => invoice.items.tickets.contains(members.elementAt(index)));
                      int invIndex = invoices.indexOf(inv);
                      func.call(0, invIndex); 
                    } on StateError {
                      null;
                    }
                  },
                ),
              ],
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Form(
                  child: Column(
                    mainAxisSize: MainAxisSize.max,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // const Spacer(),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: TextFormField(
                                onSaved: (String? value) {
                                  members[index].name = value!;
                                },
                                initialValue: members.elementAt(index).name,
                                decoration: const InputDecoration(
                                  labelText: "Name",
                                  icon: Icon(Icons.person)
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: TextFormField(
                                onSaved: (String? value) {
                                  members[index].phone = value!;
                                },
                                initialValue: members.elementAt(index).phone,
                                decoration: const InputDecoration(
                                  labelText: "Phone",
                                  icon: Icon(Icons.phone)
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: TextFormField(
                                onSaved: (String? value) {
                                  members[index].email = value!;
                                },
                                initialValue: members.elementAt(index).email,
                                decoration: const InputDecoration(
                                  labelText: "Email",
                                  icon: Icon(Icons.email)
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: TextFormField(
                                onSaved: (String? value) {
                                  var temp = value?.split(', ');
                                  members[index].location = Location(temp!.last, temp.first);
                                },
                                initialValue: members.elementAt(index).location.city + ", " + members.elementAt(index).location.state,
                                decoration: const InputDecoration(
                                  labelText: "Location",
                                  icon: Icon(Icons.location_city)
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [                              
                          Padding(
                            padding: const EdgeInsets.all(25.0),
                            child: Column(
                              children: [
                                Text("T-Shirt Size", style: Theme.of(context).textTheme.headline5,),
                                Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: DropdownButton(
                                    hint: const Text("Select Size"),
                                    value: members.elementAt(index).tSize,
                                    dropdownColor: Colors.white,
                                    style: const TextStyle(color: Colors.black),
                                    items: List.generate(TshirtSize.values.length, (index) {
                                      return DropdownMenuItem<TshirtSize>(
                                        value: TshirtSize.values.elementAt(index), 
                                        child: Padding(
                                          padding: const EdgeInsets.all(8.0),
                                          child: Text(
                                            TshirtSize.values.elementAt(index).toString().split('.')[1].split("_").join(" "),
                                            style: const TextStyle(
                                              color: Colors.black
                                            ),
                                          ),
                                        )
                                      );
                                    }),
                                    onChanged: (newSize) {
                                      setState(() {
                                        members.elementAt(index).tSize = newSize as TshirtSize;
                                      });
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ]
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [                              
                          Padding(
                            padding: const EdgeInsets.all(15.0),
                            child: StatefulBuilder(
                              builder: (BuildContext context, StateSetter setState) {
                                return Row(
                                  children: [
                                    Checkbox(value: members.elementAt(index).isDirectoryMember, onChanged: (changed) {
                                      setState(
                                        () {
                                          members.elementAt(index).isDirectoryMember = changed!;
                                        }
                                      );
                                    }),
                                    Text("Add to Directory?", style: Theme.of(context).textTheme.headline5,),
                                  ],
                                );
                              },
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(15.0),
                            child: StatefulBuilder(
                              builder: (BuildContext context, StateSetter setState) {
                                return Row(
                                  children: [
                                    Checkbox(value: members.elementAt(index).UTA, onChanged: (changed) {
                                      setState(
                                        () {
                                          members.elementAt(index).UTA = changed!;
                                        }
                                      );
                                    }),
                                    Text("Unlikely To Attend?", style: Theme.of(context).textTheme.headline5,),
                                  ],
                                );
                              },
                            ),
                          )
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(30.0),
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                primary: Colors.blueGrey[400]
                              ),
                              onPressed: () {selectDOB(index);}, 
                              child: Text("DOB: " + DateFormat("MMM dd, yyyy").format(dobs[members.elementAt(index)] as DateTime))
                            ),
                          ),
                          // const Spacer()
                        ],
                      ),
                    ],
                  ),
                  key: formKeys.elementAt(index),
                ),
              ),
              bottomAppBar: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  children: [ElevatedButton(
                    onPressed: () {
                      formKeys.elementAt(index).currentState?.save();
                      FamilyMember member = members.elementAt(index);
                      db.child(member.id).set(
                        FamilyMember.toMap(member)
                      );
                      setState(() {
                        loadMembers();
                      });
                    },
                    child: const Text("Submit Changes")
                  )],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
