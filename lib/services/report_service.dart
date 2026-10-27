import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';

class ReportService {
  static Future<void> export({required Map<String,Object?> business, required DateTime start, required DateTime end, required List<Map<String,Object?>> orders, required List<Map<String,Object?>> payments}) async {
    final pdf = pw.Document();
    final fmt = DateFormat('dd/MM/yyyy');
    final currency = (num n) => 'S/ ${n.toStringAsFixed(2)}';
    final incoming = orders.where((o) {final d=DateTime.tryParse('${o['created_at']}'); return d!=null && !d.isBefore(start) && d.isBefore(end.add(const Duration(days:1)));}).toList();
    final cash = payments.where((p) {final d=DateTime.tryParse('${p['paid_at']}'); return d!=null && !d.isBefore(start) && d.isBefore(end.add(const Duration(days:1)));}).toList();
    final advances = cash.where((p)=>p['kind']=='Adelanto').fold<double>(0,(a,p)=>a+(p['amount'] as num).toDouble());
    final delivery = cash.where((p)=>p['kind']=='Entrega').fold<double>(0,(a,p)=>a+(p['amount'] as num).toDouble());
    final pending = orders.where((o)=>o['status']!='Cancelado').fold<double>(0,(a,o)=>a+(o['total'] as num).toDouble()-(o['paid_total'] as num).toDouble());
    pw.MemoryImage? logo;
    final path='${business['logo_path']??''}';
    if(path.isNotEmpty && await File(path).exists()) logo=pw.MemoryImage(await File(path).readAsBytes());
    final counts=<String,int>{};
    for(final o in incoming){final problem='${o['problem']}'; counts[problem]=(counts[problem]??0)+1;}
    final common=counts.entries.toList()..sort((a,b)=>b.value.compareTo(a.value));
    pdf.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(35), build:(context)=>[
      pw.Row(children:[if(logo!=null) pw.Image(logo,width:65,height:65),pw.SizedBox(width:14),pw.Expanded(child:pw.Column(crossAxisAlignment:pw.CrossAxisAlignment.start,children:[pw.Text('${business['name']??'Mi negocio'}',style:pw.TextStyle(fontSize:19,fontWeight:pw.FontWeight.bold)),pw.Text('${business['phone']??''}   ${business['address']??''}',style:const pw.TextStyle(fontSize:9))]))]),
      pw.Divider(),pw.SizedBox(height:12),pw.Text('INFORME DE SERVICIOS Y MOVIMIENTOS',style:pw.TextStyle(fontSize:15,fontWeight:pw.FontWeight.bold)),pw.Text('Desde ${fmt.format(start)} hasta ${fmt.format(end)}'),pw.SizedBox(height:16),
      pw.Text('Resumen de servicios',style:pw.TextStyle(fontWeight:pw.FontWeight.bold)),
      pw.Bullet(text:'Equipos ingresados: ${incoming.length}'),pw.Bullet(text:'Reparados: ${incoming.where((o)=>['Reparado','Entregado'].contains(o['status'])).length}'),pw.Bullet(text:'Entregados: ${incoming.where((o)=>o['status']=='Entregado').length}'),pw.Bullet(text:'Cancelados: ${incoming.where((o)=>o['status']=='Cancelado').length}'),pw.Bullet(text:'En lista negra: ${incoming.where((o)=>o['status']=='Lista negra').length}'),
      pw.SizedBox(height:12),pw.Text('Movimientos económicos del período',style:pw.TextStyle(fontWeight:pw.FontWeight.bold)),
      pw.Bullet(text:'Adelantos recibidos: ${currency(advances)}'),pw.Bullet(text:'Cobros por entrega: ${currency(delivery)}'),pw.Bullet(text:'Total cobrado: ${currency(advances+delivery)}'),pw.Bullet(text:'Saldo pendiente actual de todas las órdenes activas: ${currency(pending)}'),
      pw.Text('Nota: el total cobrado representa ingresos, no ganancia neta (faltan costos).',style:const pw.TextStyle(fontSize:9)),
      pw.SizedBox(height:12),pw.Text('Fallas más comunes',style:pw.TextStyle(fontWeight:pw.FontWeight.bold)),
      ...common.take(12).map((e)=>pw.Bullet(text:'${e.key}: ${e.value}')),
      pw.SizedBox(height:12),pw.Text('Órdenes recibidas en el período',style:pw.TextStyle(fontWeight:pw.FontWeight.bold)),
      pw.Table.fromTextArray(headers:['N°','Cliente','Equipo','Estado','Total'],data:incoming.map((o)=>['${o['id']}','${o['client_name']}','${o['device_type']} ${o['model']}','${o['status']}',currency(o['total'] as num)]).toList(),cellStyle:const pw.TextStyle(fontSize:8),headerStyle:pw.TextStyle(fontSize:8,fontWeight:pw.FontWeight.bold)),
    ]));
    await Printing.layoutPdf(onLayout: (_) async => pdf.save(), name:'Informe_${DateFormat('yyyyMMdd').format(start)}_${DateFormat('yyyyMMdd').format(end)}.pdf');
  }
  static Future<void> internExport({required Map<String,Object?> business,required Map<String,Object?> intern,required List<Map<String,Object?>> records,required DateTime start,required DateTime end}) async {
    final pdf=pw.Document();
    final fmt=DateFormat('dd/MM/yyyy');
    pw.MemoryImage? logo;
    final logoPath='${business['logo_path']??''}';
    if(logoPath.isNotEmpty&&await File(logoPath).exists())logo=pw.MemoryImage(await File(logoPath).readAsBytes());
    final complete=records.where((r)=>r['exit_at']!=null).toList();
    final minutes=complete.fold<int>(0,(sum,r){final a=DateTime.tryParse('${r['entry_at']}');final b=DateTime.tryParse('${r['exit_at']}');return sum+(a!=null&&b!=null?b.difference(a).inMinutes.clamp(0,1440):0);});
    final data=records.map((r){final a=DateTime.tryParse('${r['entry_at']}');final b=DateTime.tryParse('${r['exit_at']}');final mins=a!=null&&b!=null?b.difference(a).inMinutes.clamp(0,1440):0;return [fmt.format(DateTime.parse('${r['work_date']}')),a==null?'—':DateFormat('HH:mm').format(a),b==null?'Pendiente':DateFormat('HH:mm').format(b),b==null?'—':'${(mins/60).toStringAsFixed(2)} h'];}).toList();
    pdf.addPage(pw.MultiPage(pageFormat:PdfPageFormat.a4,margin:const pw.EdgeInsets.all(36),build:(ctx)=>[
      pw.Row(children:[if(logo!=null)pw.Image(logo,width:65,height:65),pw.SizedBox(width:14),pw.Expanded(child:pw.Column(crossAxisAlignment:pw.CrossAxisAlignment.start,children:[pw.Text('${business['name']??'Mi negocio'}',style:pw.TextStyle(fontSize:18,fontWeight:pw.FontWeight.bold)),pw.Text('${business['address']??''} · ${business['phone']??''}',style:const pw.TextStyle(fontSize:9))]))]),
      pw.Divider(),pw.SizedBox(height:12),pw.Center(child:pw.Text('INFORME DE ASISTENCIA DE PRACTICANTE',style:pw.TextStyle(fontSize:15,fontWeight:pw.FontWeight.bold))),pw.SizedBox(height:14),
      pw.Text('Practicante: ${intern['name']}'),pw.Text('Institución: ${intern['institution']??''}'),pw.Text('Período: ${fmt.format(start)} al ${fmt.format(end)}'),pw.SizedBox(height:12),
      pw.Text('Días con entrada: ${records.length}'),pw.Text('Días con entrada y salida: ${complete.length}'),pw.Text('Horas trabajadas registradas: ${(minutes/60).toStringAsFixed(2)}'),pw.SizedBox(height:16),
      pw.Table.fromTextArray(headers:['Fecha','Entrada','Salida','Horas'],data:data,cellStyle:const pw.TextStyle(fontSize:9),headerStyle:pw.TextStyle(fontSize:9,fontWeight:pw.FontWeight.bold)),
      pw.SizedBox(height:42),pw.Center(child:pw.Text('________________________________')),pw.Center(child:pw.Text('Firma del responsable del taller',style:const pw.TextStyle(fontSize:10))),
    ]));
    await Printing.layoutPdf(onLayout:(_)async=>pdf.save(),name:'Asistencia_${intern['id']}_${DateFormat('yyyyMMdd').format(start)}.pdf');
  }

}
