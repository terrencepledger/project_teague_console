import 'dart:convert';
import 'package:firebase/firebase.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart';
import 'package:http_auth/http_auth.dart';
import 'package:intl/intl.dart';
import 'package:project_teague_console/project_objects.dart';

class Paypal {

  String domain = "https://api-m.paypal.com"; // for production mode
  // String domain = "https://api-m.sandbox.paypal.com";
  //// change clientId and secret with your own, provided by paypal
  String clientId = 'AQnM22JZoTqwT0WHk7CA-eaTFRNLyCHf0Rwzh_k66CgELkIfkL9d9M-IDAbBCO3uzSwUVtS7fxFI0wpJ';
  String secret = 'EFd4DQGN88XavS9pNSny8kzs2P1WDkVq9O9TZIK09pBII_heNalAmQ2mAaPjH9FI0fNJOhoWnXHPiF97';

  BuildContext context;

  late BasicAuthClient client;

  Paypal(this.context) {
    client = BasicAuthClient(clientId, secret);
  }

  Future<Response> createInvoice(FamilyMember hoh, InvoiceItems items) async {

    int invNum = int.parse(json.decode(
      (await client.post(Uri.parse('$domain/v2/invoicing/generate-next-invoice-number'))).body
    )["invoice_number"]);

    var response = await client.post(Uri.parse('$domain/v2/invoicing/invoices'),
      headers: {"Content-Type": "application/json",}, 
      body: json.encode(
        {
          "detail": {
            "invoice_number": invNum.toString(),
            "currency_code": "USD",
            "note": "Balance must be paid by ENTER_DATE",
            "memo": "Head of Household ID: ${hoh.id}",
            "payment_term": {
              "due_date": "2022-07-01"
            },
          },
          "invoicer": {
            "name": {
              "given_name": "KC Teague",
              "surname": "Reunion"
            },
            "address": {
              "address_line_1": "6201 Yecker Ave.",
              "admin_area_2": "Kansas City",
              "admin_area_1": "KS",
              "postal_code": "66104",
              "country_code": "US"
            },
            "email": "kcteaguereunion2022@gmail.com",
            "phones": [{
              "national_number": "9137100766",
              "phone_type": "MOBILE",
              "country_code": "001"
            }],
            "website": "www.kcteague.com",
            "tax_id": "87-1386919",
            "additional_notes": "test additional notes"
          },
          "primary_recipients": [
            {
              "billing_info": {
                "name": {
                  "given_name": hoh.name.split(" ").first,
                  "surname": hoh.name.split(" ").last
                },
                "email_address": hoh.email,
                "phones": [{
                  "country_code": "001",
                  "national_number": hoh.phone,
                  "phone_type": "MOBILE"
                }],
              }
            }
          ],
          "additional_recipients": [
            {
              "email_address": "8.tpledger@kscholars.org"
            }
          ],
          "items": items.createItemList(),
          "configuration": {
            "partial_payment": {
              "allow_partial_payment": true,
            },
            "allow_tip": false,
            "tax_inclusive": false,
          },
        }
      )
    );
    
    if(response.statusCode != 200) {
      return response;
    }

    var response2 = await client.post(Uri.parse(json.decode(response.body)["href"].toString() + "/send"),
      headers: {"Content-Type": "application/json",}, 
      body: json.encode({
        "send_to_invoicer": "true",
        "send_to_recipient": "true",
        "additional_recipients": [
          {"email_address": "8.tpledger@kscholars.org"}
        ]
      })
    );

    return response2;

  }

  void getInvoices(Function(List<Invoice> temp, Report report, int count) func, Function(String errorCode, String error) onError) async {
    
    List<Invoice> ret = [];

    var response = await client.get(Uri.parse('$domain/v2/invoicing/invoices?page_size=100&total_required=true&fields=items'),
      headers: {
        "Content-Type": "application/json",
      },
    );
    
    if (response.statusCode == 200) {
      List invoices = json.decode(response.body)["items"];
      int count = 0;
      Report report = Report();
      for (var jsonInvoice in invoices) {

        Invoice? invoice = await Invoice.toInvoice(jsonInvoice);
        if((invoice.status != InvoiceStatus.Other && invoice.status != InvoiceStatus.Cancelled)) {
          if(invoice.status == InvoiceStatus.Paying || invoice.status == InvoiceStatus.Sent || invoice.status == InvoiceStatus.Paid) {

            var detailedInvObj = json.decode((await client.get(invoice.url)).body);

            if(invoice.status == InvoiceStatus.Paying || invoice.status == InvoiceStatus.Paid)
            {
              invoice.paid = double.parse(detailedInvObj["payments"]["paid_amount"]["value"]);
              var transactions = detailedInvObj["payments"]["transactions"];
              for (var payment in transactions) {
                invoice.payments.add(Payment.fromMap(payment));
              }
              if(invoice.status == InvoiceStatus.Paid) {
                count++;
              }
            }
            else {
              invoice.paid = 0;
            }
            InvoiceItems items = InvoiceItems();
            for (var item in detailedInvObj["items"]) {
              switch (item["name"]) {
                case "T-Shirt Order Form Purchase":
                  TshirtSize size = TshirtSize.values.firstWhere((element) => element.name == item["description"].toString().split('T-Shirt Size: ').last.split(' ').join('_'));
                  for (var i = 0; i < int.parse(item['quantity']); i++) {
                    items.shirtsOrder.addShirt(size);
                  }
                  List<String> orderInfo = detailedInvObj["detail"]["memo"].toString().split('Order Info: ').last.split(', ');
                  items.shirtsOrder.id = orderInfo[0];
                  items.shirtsOrder.orderName = orderInfo[1];
                  items.shirtsOrder.orderEmail = orderInfo[2];
                  items.shirtsOrder.orderNumber = orderInfo[3];
                  if(orderInfo[4] != "null") {
                    items.shirtsOrder.delivery.needDelivery = true;
                    items.shirtsOrder.delivery.address = orderInfo[4];
                  }
                  invoice.items = items;
                  break;
                case "T-Shirt Purchase":
                case "Child Assessment":
                case "Adult Assessment":
                  var split = item["description"].toString().split(': ').last.split(" (");
                  String id = split.last.split(')').first;
                  FamilyMember? member;
                  await database().ref("members").child(id).once('value').then((value) async {
                    member = FamilyMember.toMember(value.snapshot.val());
                    member!.id = id;
                  });
                  invoice.items.addMember(member);
                  break;
              }
            }

          }
          report.addInvoice(invoice);
          ret.add(invoice);
        }

      }
      func.call(ret,report,count);
    }
    else {
      onError.call(response.statusCode.toString(), response.reasonPhrase.toString());
    }

  }

  Future<Response> update(Uri url, double amt) async {

    String endPoint;
    
    if(amt >= 0) {
      endPoint = "payments";
    }
    else {
      endPoint = "refunds";
      amt = amt*-1;
    }

    return client.post(Uri.parse("${url.toString()}/$endPoint"),
      headers: {"Content-Type": "application/json",},
      body: json.encode({
        "method": "OTHER",
        "payment_date": DateFormat("yyyy-MM-dd").format(DateTime.now()),
        "amount": {
          "currency_code": "USD",
          "value": amt.toStringAsFixed(2)
        }
      })
    );

  }

  Future sendReminder(BuildContext context, Invoice inv, void Function(String errorCode, String error) onError) async {

    var reminderResponse = await client.post(Uri.parse('$domain/v2/invoicing/invoices/${inv.id}/remind'),
      headers: {"Content-Type": "application/json",},
      body: json.encode({
        "subject": "Reminder: Payment due for Teague Reunion - Inv#${inv.invNum}",
        "note": "Please pay before the due date of July 01, 2022",
        "send_to_invoicer": true,   
        "additional_recipients": [
          "8.tpledger@kscholars.org",
          "pledgerm2@yahoo.com"
        ]
      })
    );

    if(reminderResponse.statusCode != 200 | 204) {
      return onError.call(reminderResponse.statusCode.toString(), reminderResponse.reasonPhrase.toString());
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Reminder successfully sent!"),
        duration: Duration(seconds: 4),
      )
    );
      
  }

}