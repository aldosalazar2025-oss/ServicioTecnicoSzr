import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:archive/archive_io.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import '../services/report_service.dart';
import '../db/database.dart';

const statuses = ['Recibido', 'En diagnóstico', 'En reparación', 'Reparado', 'Entregado', 'Cancelado', 'Lista negra'];
const devices = ['Celular', 'Laptop', 'Computadora', 'Impresora', 'Tablet', 'Otro'];
const accent = Color(0xFF00BEEB);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.isDark, required this.onToggleTheme});
  final bool isDark;
  final VoidCallback onToggleTheme;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int page = 0;
  bool loading = true;
  String search = '';
  String filter = 'Todos';
  DateTime? ordersFrom;
  DateTime? ordersTo;
  List<Map<String, Object?>> clients = [], orders = [], payments = [], interns = [], attendance = [];
  Map<String,Object?> business = {'name':'Mi negocio'};
  DateTime reportFrom = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime reportTo = DateTime.now();
  final money = NumberFormat.currency(locale: 'es_PE', symbol: 'S/ ', decimalDigits: 2);

  @override
  void initState() { super.initState(); refresh(); }
  Future<void> refresh() async {
    final db = await AppDatabase.instance;
    final c = await db.query('clients', orderBy: 'id DESC');
    final o = await db.rawQuery('''SELECT orders.*, clients.name AS client_name, clients.phone AS client_phone
      FROM orders JOIN clients ON clients.id=orders.client_id ORDER BY orders.id DESC''');
    final ps = await db.query('payments', orderBy:'id DESC');
    final bs = await db.query('business', where:'id=1');
    final ins = await db.query('interns', orderBy:'name');
    final ats = await db.query('attendance', orderBy:'entry_at DESC');
    final totals = <int,double>{};
    for(final payment in ps){ final id=payment['order_id'] as int; totals[id]=(totals[id]??0)+(payment['amount'] as num).toDouble(); }
    final enriched=o.map((row)=> <String,Object?>{...row,'paid_total':totals[row['id']]??0.0}).toList();
    if (mounted) setState(() { clients = c; orders = enriched; payments=ps; interns=ins; attendance=ats; business=bs.isEmpty?{'name':'Mi negocio'}:bs.first; loading = false; });
  }

  Future<void> quickStatus(Map<String, Object?> order, String status) async {
    if (status == order['status']) return;
    if(status=='Entregado'){await deliver(order);return;}
    if(status=='Lista negra'){await blacklistOrder(order);return;}
    final db = await AppDatabase.instance;
    await db.update('orders', {'status': status}, where: 'id=?', whereArgs: [order['id']]);
    await refresh();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Orden #${order['id']}: $status'), duration: const Duration(seconds: 2)));
  }

  Widget formTitle(String label) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
      decoration: BoxDecoration(color: dark ? const Color(0xFF163A49) : const Color(0xFFE0F5FC), borderRadius: BorderRadius.circular(13)),
      child: Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800, color: dark ? const Color(0xFF75DFFF) : const Color(0xFF006B91))));
  }

  Future<bool> confirmDelete(String title, String detail) async => await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
    title:formTitle(title), content:SizedBox(width:420,child:Text(detail)), actions:[
      TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancelar')),
      FilledButton(onPressed:()=>Navigator.pop(ctx,true),style:FilledButton.styleFrom(backgroundColor:Colors.red.shade700),child:const Text('Eliminar definitivamente'))])) ?? false;

  Future<void> deleteOrder(Map<String,Object?> order) async {
    if(!await confirmDelete('Eliminar orden #${order['id']}', 'Se borrarán la reparación, los adelantos, pagos, ganancias y registro en lista negra. Los informes se recalcularán. Esta acción no se puede deshacer.'))return;
    final db=await AppDatabase.instance;
    await db.transaction((t) async {
      await t.delete('payments',where:'order_id=?',whereArgs:[order['id']]);
      await t.delete('blacklist',where:'order_id=?',whereArgs:[order['id']]);
      await t.delete('orders',where:'id=?',whereArgs:[order['id']]);
    }); await refresh();
  }
  Future<void> deleteAllOrders() async {
    if(!await confirmDelete('Eliminar TODAS las órdenes', 'Se eliminarán todas las órdenes y TODOS los pagos y adelantos. Exporta antes una copia de seguridad.'))return;
    final db=await AppDatabase.instance;
    await db.transaction((t)async{await t.delete('payments');await t.delete('blacklist');await t.delete('orders');}); await refresh();
  }
  Future<void> deleteClient(Map<String,Object?> c) async {
    if(orders.any((o)=>o['client_id']==c['id'])) {if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Este cliente tiene órdenes. Elimina primero sus órdenes.')));return;}
    if(!await confirmDelete('Eliminar cliente', '¿Eliminar definitivamente a ${c['name']}?'))return;
    final db=await AppDatabase.instance;await db.delete('clients',where:'id=?',whereArgs:[c['id']]);await refresh();
  }
  Future<void> deleteAllClients() async {
    if(orders.isNotEmpty){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Primero elimina las órdenes para evitar clientes con reparaciones vinculadas.')));return;}
    if(!await confirmDelete('Eliminar TODOS los clientes','Se eliminarán todos los clientes registrados. Esta acción no se puede deshacer.'))return;
    final db=await AppDatabase.instance;await db.delete('clients');await refresh();
  }

  Widget field(String label, TextEditingController controller, {bool required = false, bool numeric = false, int lines = 1, ValueChanged<String>? changed}) => Padding(
    padding: const EdgeInsets.only(bottom: 13),
    child: TextFormField(controller: controller, maxLines: lines,
      keyboardType: numeric ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      onChanged: changed,
      validator: (v) => required && (v == null || v.trim().isEmpty) ? 'Este campo es obligatorio' : null,
      decoration: InputDecoration(labelText: label, contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15))));

  Widget pair(Widget a, Widget b) => LayoutBuilder(builder:(ctx,c)=>c.maxWidth<560 ? Column(children:[a,b]) : Row(crossAxisAlignment:CrossAxisAlignment.start,children:[Expanded(child:a),const SizedBox(width:14),Expanded(child:b)]));

  Future<void> deliver(Map<String,Object?> order) async {
    final remaining=((order['total'] as num).toDouble()-(order['paid_total'] as num).toDouble()).clamp(0,double.infinity).toDouble();
    final amount=TextEditingController(text:remaining.toStringAsFixed(2));
    final accepted=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:formTitle('Confirmar entrega de dispositivo'),content:SizedBox(width:440,child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[Text('Orden #${order['id']} · ${order['client_name']}'),Text('${order['device_type']} ${order['model']}'),const SizedBox(height:12),Text('Precio total: ${money.format(order['total'])}'),Text('Ya cobrado: ${money.format(order['paid_total'])}'),Text('Saldo pendiente: ${money.format(remaining)}',style:const TextStyle(fontWeight:FontWeight.bold)),const SizedBox(height:12),field('Pago al entregar (S/)',amount,numeric:true),const Text('Si el pago es parcial, el saldo continuará pendiente.',style:TextStyle(fontSize:12))])),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancelar')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Confirmar entrega y pago'))]));
    if(accepted!=true)return;
    final value=double.tryParse(amount.text.replaceAll(',','.'));
    if(value==null || value<0 || value>remaining){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('El monto no es válido.')));return;}
    final db=await AppDatabase.instance;
    await db.transaction((txn)async{
      if(value>0)await txn.insert('payments',{'order_id':order['id'],'amount':value,'kind':'Entrega','paid_at':DateTime.now().toIso8601String()});
      await txn.update('orders',{'status':'Entregado','delivery_at':DateTime.now().toIso8601String()},where:'id=?',whereArgs:[order['id']]);
      await txn.delete('blacklist',where:'order_id=?',whereArgs:[order['id']]);
    });
    await refresh();
  }

  Future<void> blacklistOrder(Map<String,Object?> order) async {
    final reason=TextEditingController();
    final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:formTitle('Enviar a lista negra'),content:SizedBox(width:450,child:Column(mainAxisSize:MainAxisSize.min,children:[Text('Orden #${order['id']}. Registra el motivo por el que no se recogió el equipo.'),const SizedBox(height:12),field('Motivo *',reason,lines:2)])),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancelar')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Confirmar'))]));
    if(ok!=true||reason.text.trim().isEmpty)return;
    final db=await AppDatabase.instance;
    await db.transaction((txn)async{await txn.insert('blacklist',{'order_id':order['id'],'reason':reason.text.trim(),'added_at':DateTime.now().toIso8601String()},conflictAlgorithm:ConflictAlgorithm.replace);await txn.update('orders',{'status':'Lista negra'},where:'id=?',whereArgs:[order['id']]);});
    await refresh();
  }

  Future<void> removeBlacklist(Map<String,Object?> order) async {
    final db=await AppDatabase.instance;
    await db.transaction((txn)async{await txn.delete('blacklist',where:'order_id=?',whereArgs:[order['id']]);await txn.update('orders',{'status':'Reparado'},where:'id=?',whereArgs:[order['id']]);});
    await refresh();
  }

  Future<void> businessDialog() async {
    final fields={for(final k in ['name','owner','phone','address','email','ruc'])k:TextEditingController(text:'${business[k]??''}')};
    String logoPath='${business['logo_path']??''}';
    await showDialog(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,change)=>AlertDialog(title:formTitle('Mi negocio · Configuración'),content:SizedBox(width:640,height:490,child:SingleChildScrollView(child:Column(children:[
      pair(field('Nombre comercial *',fields['name']!,required:true),field('Propietario',fields['owner']!)),
      pair(field('Teléfono',fields['phone']!),field('Correo',fields['email']!)),
      pair(field('Dirección',fields['address']!),field('RUC',fields['ruc']!)),
      if(logoPath.isNotEmpty && File(logoPath).existsSync())Image.file(File(logoPath),width:120,height:100,fit:BoxFit.contain),
      OutlinedButton.icon(onPressed:()async{final result=await FilePicker.platform.pickFiles(type:FileType.custom,allowedExtensions:['png','jpg','jpeg']);if(result==null||result.files.single.path==null)return;final support=await getApplicationSupportDirectory();final dir=Directory(path.join(support.path,'ServicioTecnicoPro','business'));await dir.create(recursive:true);final ext=path.extension(result.files.single.path!);final dest=path.join(dir.path,'logo$ext');await File(result.files.single.path!).copy(dest);change(()=>logoPath=dest);},icon:const Icon(Icons.upload_file),label:const Text('Subir logo PNG/JPG')),
    ]))),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancelar')),FilledButton(onPressed:()async{if(fields['name']!.text.trim().isEmpty)return;final db=await AppDatabase.instance;await db.insert('business',{'id':1,...{for(final e in fields.entries)e.key:e.value.text.trim()},'logo_path':logoPath},conflictAlgorithm:ConflictAlgorithm.replace);if(ctx.mounted)Navigator.pop(ctx);await refresh();},child:const Text('Guardar datos'))])));
  }

  Future<void> pickReportDate(bool start) async {
    final date=await showDatePicker(context:context,initialDate:start?reportFrom:reportTo,firstDate:DateTime(2020),lastDate:DateTime(2100));
    if(date!=null)setState((){if(start)reportFrom=date;else reportTo=date;});
  }

  Future<void> clientDialog([Map<String, Object?>? old]) async {
    final name = TextEditingController(text: '${old?['name'] ?? ''}');
    final phone = TextEditingController(text: '${old?['phone'] ?? ''}');
    final email = TextEditingController(text: '${old?['email'] ?? ''}');
    final document = TextEditingController(text: '${old?['document'] ?? ''}');
    final key = GlobalKey<FormState>();
    await showDialog(context: context, builder: (ctx) => AlertDialog(
      title: formTitle(old == null ? 'Nuevo cliente' : 'Editar cliente'),
      content: SizedBox(width: 480, child: Form(key: key, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        field('Nombre completo *', name, required: true), field('Teléfono *', phone, required: true),
        pair(field('Correo (opcional)', email), field('DNI (opcional)', document)),
      ])))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        FilledButton(onPressed: () async {
          if (!key.currentState!.validate()) return;
          final db = await AppDatabase.instance;
          final data = <String, Object?>{'name': name.text.trim(), 'phone': phone.text.trim(), 'email': email.text.trim(), 'document': document.text.trim()};
          if (old == null) { await db.insert('clients', {...data, 'created_at': DateTime.now().toIso8601String()}); }
          else { await db.update('clients', data, where: 'id=?', whereArgs: [old['id']]); }
          if (ctx.mounted) Navigator.pop(ctx);
          await refresh();
        }, child: const Text('Guardar cliente'))],
    ));
  }

  Future<void> pickOrdersDate(bool from) async {
    final chosen = await showDatePicker(
      context: context,
      initialDate: (from ? ordersFrom : ordersTo) ?? DateTime.now(),
      firstDate: DateTime(2000), lastDate: DateTime(2100),
    );
    if (chosen != null && mounted) setState(() {
      if (from) { ordersFrom = chosen; } else { ordersTo = chosen; }
    });
  }

  Future<void> orderDialog([Map<String, Object?>? old]) async {
    final linked = old == null ? null : clients.where((c) => c['id'] == old['client_id']).firstOrNull;
    final name = TextEditingController(text: '${linked?['name'] ?? ''}');
    final phone = TextEditingController(text: '${linked?['phone'] ?? ''}');
    final email = TextEditingController(text: '${linked?['email'] ?? ''}');
    final document = TextEditingController(text: '${linked?['document'] ?? ''}');
    final brand = TextEditingController(text: '${old?['brand'] ?? ''}');
    final model = TextEditingController(text: '${old?['model'] ?? ''}');
    final serial = TextEditingController(text: '${old?['serial'] ?? ''}');
    final problem = TextEditingController(text: '${old?['problem'] ?? ''}');
    final work = TextEditingController(text: '${old?['work'] ?? ''}');
    final notes = TextEditingController(text: '${old?['notes'] ?? ''}');
    final total = TextEditingController(text: '${old?['total'] ?? '0'}');
    final advance = TextEditingController(text: '${old?['advance'] ?? '0'}');
    final form = GlobalKey<FormState>();
    DateTime receivedAt = DateTime.tryParse('${old?['created_at'] ?? ''}') ?? DateTime.now();
    String receiverChoice = old == null ? 'owner' :
        ('${old['received_by_type'] ?? 'owner'}' == 'intern' ? 'intern' : 'owner');
    int? receiverInternId;
    if (receiverChoice == 'intern') {
      for (final person in interns) {
        if ('${person['name']}' == '${old?['received_by']}') {
          receiverInternId = person['id'] as int;
          break;
        }
      }
    }
    final receptionHour = TextEditingController(text: DateFormat('HH:mm').format(receivedAt));
    String type = '${old?['device_type'] ?? devices.first}';
    String status = '${old?['status'] ?? statuses.first}';
    int? selectedClient = old?['client_id'] as int?;
    bool explicitlyNew = false;
    List<Map<String, Object?>> matches = [];
    void findMatches(void Function(void Function()) update) {
      if (old != null || explicitlyNew) return;
      final n = name.text.trim().toLowerCase();
      final p = phone.text.trim();
      update(() => matches = (n.length >= 3 || p.length >= 4) ? clients.where((c) {
        final cn = '${c['name']}'.toLowerCase();
        final cp = '${c['phone']}';
        return (n.length >= 3 && cn.contains(n)) || (p.length >= 4 && cp.contains(p));
      }).take(4).toList() : []);
    }
    await showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, update) => AlertDialog(
      title: formTitle(old == null ? 'Nueva orden de reparación' : 'Editar orden #${old['id']}'),
      content: SizedBox(width: 760, height: 580, child: Form(key: form, child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        section('RECEPCIÓN DEL EQUIPO'),
        pair(
          OutlinedButton.icon(
            onPressed: () async {
              final picked = await showDatePicker(context: ctx,
                initialDate: receivedAt, firstDate: DateTime(2000), lastDate: DateTime(2100));
              if (picked != null) update(() => receivedAt = DateTime(
                picked.year, picked.month, picked.day, receivedAt.hour, receivedAt.minute));
            },
            icon: const Icon(Icons.calendar_today_outlined),
            label: Text('Fecha: ${DateFormat('dd/MM/yyyy').format(receivedAt)}'),
          ),
          TextFormField(controller: receptionHour,
            decoration: const InputDecoration(labelText: 'Hora (HH:mm)', prefixIcon: Icon(Icons.access_time)),
            validator: (value) {
              final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch((value ?? '').trim());
              if (match == null) return 'Usa HH:mm';
              final h = int.parse(match.group(1)!); final m = int.parse(match.group(2)!);
              return h < 24 && m < 60 ? null : 'Hora no válida';
            }),
        ),
        const SizedBox(height: 22),
        DropdownButtonFormField<String>(
          value: receiverChoice,
          decoration: const InputDecoration(labelText: 'Recibido / registrado por'),
          items: const [
            DropdownMenuItem(value: 'owner', child: Text('Dueño del negocio')),
            DropdownMenuItem(value: 'intern', child: Text('Practicante registrado')),
          ],
          onChanged: (value) => update(() { receiverChoice = value ?? 'owner'; receiverInternId = null; }),
        ),
        if (receiverChoice == 'intern') Padding(
          padding: const EdgeInsets.only(top: 12),
          child: DropdownButtonFormField<int>(
            value: receiverInternId,
            decoration: const InputDecoration(labelText: 'Seleccionar practicante'),
            items: interns.map((person) => DropdownMenuItem<int>(
              value: person['id'] as int, child: Text('${person['name']}'))).toList(),
            validator: (value) => value == null ? 'Selecciona un practicante' : null,
            onChanged: (value) => update(() => receiverInternId = value),
          ),
        ),
        const SizedBox(height: 12),
        section('DATOS DEL CLIENTE'),
        if (selectedClient != null) Card(color: Theme.of(ctx).colorScheme.primaryContainer, child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [
          const Icon(Icons.verified_outlined), const SizedBox(width: 10), Expanded(child: Text('Cliente existente vinculado: ${name.text}')),
          if (old == null) TextButton(onPressed: () => update(() { selectedClient = null; explicitlyNew = true; matches = []; }), child: const Text('Usar otro')),
        ]))),
        pair(field('Nombre completo *', name, required: true, changed: (_) { if (selectedClient != null && old == null) selectedClient = null; findMatches(update); }), field('Teléfono *', phone, required: true, changed: (_) { if (selectedClient != null && old == null) selectedClient = null; findMatches(update); })),
        if (matches.isNotEmpty && selectedClient == null) Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('¿Es alguno de estos clientes?', style: TextStyle(fontWeight: FontWeight.w700)),
          ...matches.map((c) => ListTile(dense: true, leading: const Icon(Icons.person_search_outlined), title: Text('${c['name']}'), subtitle: Text('${c['phone']}'), trailing: const Text('Seleccionar'), onTap: () => update(() {
            selectedClient = c['id'] as int; name.text = '${c['name']}'; phone.text = '${c['phone']}'; email.text = '${c['email'] ?? ''}'; document.text = '${c['document'] ?? ''}'; matches = [];
          }))),
          TextButton(onPressed: () => update(() { explicitlyNew = true; matches = []; }), child: const Text('No es ninguno, crear cliente nuevo')),
        ]))),
        pair(field('Correo (opcional)', email), field('DNI (opcional)', document)),
        section('DATOS DEL EQUIPO'),
        pair(DropdownButtonFormField<String>(initialValue: type, decoration: const InputDecoration(labelText: 'Tipo de dispositivo'), items: devices.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(), onChanged: (v) => update(() => type = v!)), field('Marca', brand)),
        pair(field('Modelo *', model, required: true), field('IMEI / número de serie', serial)),
        field('Falla reportada *', problem, required: true, lines: 2), field('Trabajo a realizar', work, lines: 2),
        DropdownButtonFormField<String>(initialValue: status, decoration: const InputDecoration(labelText: 'Estado'), items: statuses.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(), onChanged: (v) => update(() => status = v!)),
        const SizedBox(height: 18), section('PRESUPUESTO'),
        pair(field('Precio total (S/)', total, numeric: true, changed: (_) => update(() {})), field('Adelanto (S/)', advance, numeric: true, changed: (_) => update(() {}))),
        Padding(padding: const EdgeInsets.only(bottom: 14), child: Text('Saldo pendiente: ${money.format((double.tryParse(total.text.replaceAll(',', '.')) ?? 0) - (double.tryParse(advance.text.replaceAll(',', '.')) ?? 0))}', style: const TextStyle(fontWeight: FontWeight.bold))),
        field('Observaciones del técnico', notes, lines: 3),
      ])))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        FilledButton.icon(icon: const Icon(Icons.save_outlined), label: const Text('Guardar orden'), onPressed: () async {
          if (!form.currentState!.validate()) return;
          final price = double.tryParse(total.text.trim().replaceAll(',', '.'));
          final paid = double.tryParse(advance.text.trim().replaceAll(',', '.'));
          if (price == null || paid == null || price < 0 || paid < 0 || paid > price) {
            ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Precio y adelanto deben ser válidos; el adelanto no puede superar el total.'))); return;
          }
          if(old!=null && paid < (old['advance'] as num).toDouble()){ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content:Text('No se puede reducir el adelanto ya registrado.')));return;}
          final timeParts = receptionHour.text.trim().split(':');
          final receptionDateTime = DateTime(receivedAt.year, receivedAt.month,
              receivedAt.day, int.parse(timeParts[0]), int.parse(timeParts[1]));
          String receiverName = '${business['name'] ?? ''}'.trim();
          if (receiverName.isEmpty) receiverName = 'Mi negocio';
          if (receiverChoice == 'intern') {
            final chosen = interns.where((p) => p['id'] == receiverInternId).first;
            receiverName = '${chosen['name']}';
          }
          final db = await AppDatabase.instance;
          await db.transaction((txn) async {
            int clientId;
            if (selectedClient != null) {
              clientId = selectedClient!;
              if (old != null) await txn.update('clients', {'name': name.text.trim(), 'phone': phone.text.trim(), 'email': email.text.trim(), 'document': document.text.trim()}, where: 'id=?', whereArgs: [clientId]);
            } else {
              clientId = await txn.insert('clients', {'name': name.text.trim(), 'phone': phone.text.trim(), 'email': email.text.trim(), 'document': document.text.trim(), 'created_at': DateTime.now().toIso8601String()});
            }
            final data = <String, Object?>{'client_id': clientId, 'device_type': type, 'brand': brand.text.trim(), 'model': model.text.trim(), 'serial': serial.text.trim(), 'problem': problem.text.trim(), 'work': work.text.trim(), 'notes': notes.text.trim(), 'status': status, 'total': price, 'advance': paid, 'created_at': receptionDateTime.toIso8601String(), 'received_by': receiverName, 'received_by_type': receiverChoice};
            if (old == null) {
              final created=receptionDateTime.toIso8601String();
              final nextNumber = await txn.rawQuery('SELECT COALESCE(MAX(order_no), 0) + 1 AS next_no FROM orders');
              data['order_no'] = nextNumber.first['next_no'] as int;
              final orderId=await txn.insert('orders', data);
              if(paid>0)await txn.insert('payments',{'order_id':orderId,'amount':paid,'kind':'Adelanto','paid_at':created});
            } else {
              final existing=(old['advance'] as num).toDouble();
              final delta=paid-existing;
              if(delta<0){throw StateError('No se puede reducir un adelanto registrado; registra un ajuste de pago por separado.');}
              await txn.update('orders', data, where: 'id=?', whereArgs: [old['id']]);
              if(delta>0)await txn.insert('payments',{'order_id':old['id'],'amount':delta,'kind':'Adelanto','paid_at':DateTime.now().toIso8601String()});
            }
          });
          if (ctx.mounted) Navigator.pop(ctx);
          await refresh();
        })],
    )));
  }

  Widget section(String title) => Padding(padding: const EdgeInsets.only(top: 10, bottom: 12), child: Text(title, style: const TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.2)));

  Color statusColor(String s) => switch (s) {
    'Recibido' => const Color(0xFF6478C8),
    'En diagnóstico' => const Color(0xFFE0A33C),
    'En reparación' => const Color(0xFFAE83E8),
    'Reparado' => const Color(0xFF31AA79),
    'Entregado' => const Color(0xFF249DAB),
    _ => const Color(0xFFD06B76),
  };

  Widget pill(String s) { final c = statusColor(s); return Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7), decoration: BoxDecoration(color: c.withValues(alpha: .13), borderRadius: BorderRadius.circular(9)), child: Text(s, style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w700))); }
  Widget nav(int i, IconData icon, String title) => Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3), child: Material(color: page == i ? accent.withValues(alpha: .15) : Colors.transparent, borderRadius: BorderRadius.circular(12), child: ListTile(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), dense: true, selected: page == i, selectedColor: accent, leading: Icon(icon, size: 21), title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)), onTap: () => setState(() { page = i; search = ''; filter = 'Todos'; }))));

  Widget stat(String title, String value, IconData icon, Color color) => Container(
    padding: const EdgeInsets.all(19), decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: .25))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Flexible(child: Text(title, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant))), Icon(icon, color: color, size: 21)]), const SizedBox(height: 16), Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800))]));

  Widget orderCard(Map<String, Object?> o) {
    final total = (o['total'] as num).toDouble(); final paid = (o['paid_total'] as num).toDouble();
    final status = '${o['status']}';
    final date = DateTime.tryParse('${o['created_at']}');
    return Card(margin: const EdgeInsets.only(bottom: 11), elevation: 0, child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Container(width: 43, height: 43, decoration: BoxDecoration(color: accent.withValues(alpha: .12), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.devices_other_outlined, color: accent)), const SizedBox(width: 13),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('ORD-${((o['order_no'] as int?) ?? (o['id'] as int)).toString().padLeft(4, '0')}  ·  ${o['device_type']} ${o['brand']} ${o['model']}', overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)), const SizedBox(height: 4), Text('${o['client_name']}  ·  ${o['client_phone']}', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13))])),
        pill(status), const SizedBox(width: 10), PopupMenuButton<String>(tooltip: 'Cambiar estado sin editar', onSelected: (s) => quickStatus(o, s), itemBuilder: (_) => statuses.map((s) => PopupMenuItem(value: s, child: Row(children: [Icon(s == status ? Icons.check_circle : Icons.circle_outlined, size: 17, color: statusColor(s)), const SizedBox(width: 9), Text(s)]))).toList(), child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.more_vert))),
        IconButton(tooltip: 'Editar orden', onPressed: () => orderDialog(o), icon: const Icon(Icons.edit_outlined, size: 20)),
        IconButton(tooltip:'Eliminar orden y sus pagos',onPressed:()=>deleteOrder(o),icon:const Icon(Icons.delete_outline,color:Colors.redAccent)),
      ]),
      const SizedBox(height: 12), Text('${o['problem']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      const SizedBox(height: 13), Divider(color: Theme.of(context).dividerColor.withValues(alpha: .3)),
      Wrap(spacing: 22, runSpacing: 9, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text('Total: ${money.format(total)}', style: const TextStyle(fontWeight: FontWeight.w600)), Text('Cobrado: ${money.format(paid)}'), Text('Saldo: ${money.format(total - paid)}', style: TextStyle(color: total > paid ? const Color(0xFFE1A13B) : const Color(0xFF30B881), fontWeight: FontWeight.w700)),
        if (date != null) Text(DateFormat('dd/MM/yyyy HH:mm').format(date), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        Text('Recibió: ${('${o['received_by'] ?? ''}').trim().isEmpty ? 'No registrado' : o['received_by']}', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        if (status != 'Reparado' && status != 'Entregado' && status != 'Cancelado') OutlinedButton.icon(onPressed: () => quickStatus(o, 'Reparado'), icon: const Icon(Icons.check_circle_outline, size: 17), label: const Text('Marcar reparado')),
        if(status!='Entregado' && status!='Cancelado' && status!='Lista negra') OutlinedButton.icon(onPressed:()=>blacklistOrder(o),icon:const Icon(Icons.archive_outlined,size:17),label:const Text('Enviar a lista negra')),
        if(status=='Lista negra') OutlinedButton.icon(onPressed:()=>removeBlacklist(o),icon:const Icon(Icons.unarchive_outlined,size:17),label:const Text('Retirar de lista negra')),
        if(status=='Reparado'||status=='Lista negra') FilledButton.icon(onPressed:()=>deliver(o),icon:const Icon(Icons.local_shipping_outlined,size:17),label:const Text('Entregar dispositivo')),
      ]),
    ])));
  }


  Future<void> exportBackup() async {
    try {
      final db=await AppDatabase.instance;
      final support=await getApplicationSupportDirectory();
      final base=Directory(path.join(support.path,'ServicioTecnicoPro'));
      final temp=await Directory.systemTemp.createTemp('szr_backup_');
      try {
        final snapshot=path.join(temp.path,'servicio_tecnico.db');
        await db.execute("VACUUM INTO '${snapshot.replaceAll("'", "''")}'");
        final archive=Archive();
        void addFile(File file,String relative){final bytes=file.readAsBytesSync();archive.addFile(ArchiveFile(relative,bytes.length,bytes));}
        addFile(File(snapshot),'servicio_tecnico.db');
        final manifest=utf8.encode(jsonEncode({'app':'Servicio Técnico SZR','backup_version':1,'created_at':DateTime.now().toIso8601String()}));
        archive.addFile(ArchiveFile('manifest.json',manifest.length,manifest));
        if(await base.exists()) {
          for(final f in base.listSync(recursive:true).whereType<File>()){
            if(path.basename(f.path)=='servicio_tecnico.db')continue;
            final relative=path.relative(f.path,from:base.path).replaceAll('\\','/');
            addFile(f,'files/$relative');
          }
        }
        final result=await FilePicker.platform.saveFile(dialogTitle:'Guardar copia de seguridad SZR',fileName:'SZR_Backup_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.zip',type:FileType.custom,allowedExtensions:['zip']);
        if(result==null)return;
        final output=File(result.toLowerCase().endsWith('.zip')?result:'$result.zip');
        await output.writeAsBytes(ZipEncoder().encode(archive)!);
        if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Copia guardada en ${output.path}')));
      }finally{await temp.delete(recursive:true);}
    }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('No se pudo exportar: $e')));}
  }

  Future<void> restoreBackup() async {
    final picked=await FilePicker.platform.pickFiles(type:FileType.custom,allowedExtensions:['zip']);
    if(picked==null||picked.files.single.path==null)return;
    if(!await confirmDelete('Restaurar copia de seguridad','Se reemplazarán los datos actuales del taller por los del ZIP. Antes de continuar, exporta una copia de los datos actuales.'))return;
    try{
      final bytes=await File(picked.files.single.path!).readAsBytes();
      final archive=ZipDecoder().decodeBytes(bytes);
      final names=archive.files.where((f)=>f.isFile).map((f)=>f.name).toSet();
      if(!names.contains('manifest.json')||!names.contains('servicio_tecnico.db'))throw const FormatException('El ZIP no es una copia válida de SZR');
      final support=await getApplicationSupportDirectory();
      final base=Directory(path.join(support.path,'ServicioTecnicoPro'));
      final temp=await Directory.systemTemp.createTemp('szr_restore_');
      try{
        for(final entry in archive.files.where((f)=>f.isFile)){
          if(entry.name!='servicio_tecnico.db'&&!entry.name.startsWith('files/'))continue;
          final relative=entry.name=='servicio_tecnico.db'?entry.name:entry.name.substring(6);
          final normalized=path.normalize(relative);
          if(path.isAbsolute(normalized)||normalized=='..'||normalized.startsWith('..${path.separator}'))throw const FormatException('Ruta insegura en ZIP');
          final file=File(path.join(temp.path,normalized));await file.parent.create(recursive:true);await file.writeAsBytes(entry.content as List<int>);
        }
        await AppDatabase.close();
        await base.create(recursive:true);
        for(final f in temp.listSync(recursive:true).whereType<File>()){
          final rel=path.relative(f.path,from:temp.path);final dest=File(path.join(base.path,rel));await dest.parent.create(recursive:true);await f.copy(dest.path);
        }
        await refresh();
        if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Copia restaurada correctamente')));
      }finally{await temp.delete(recursive:true);}
    }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('No se pudo restaurar: $e')));}
  }

  Future<void> internDialog([Map<String,Object?>? old]) async {
    final name=TextEditingController(text:'${old?['name']??''}');
    final institution=TextEditingController(text:'${old?['institution']??''}');
    final phone=TextEditingController(text:'${old?['phone']??''}');
    await showDialog(context:context,builder:(ctx)=>AlertDialog(title:formTitle(old==null?'Nuevo practicante':'Editar practicante'),content:SizedBox(width:520,child:Column(mainAxisSize:MainAxisSize.min,children:[field('Nombres y apellidos *',name),field('Institución educativa',institution),field('Teléfono',phone)])),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancelar')),FilledButton(onPressed:()async{
      if(name.text.trim().isEmpty)return;
      final db=await AppDatabase.instance;
      final data={'name':name.text.trim(),'institution':institution.text.trim(),'phone':phone.text.trim()};
      if(old==null){await db.insert('interns',{...data,'created_at':DateTime.now().toIso8601String()});}
      else{await db.update('interns',data,where:'id=?',whereArgs:[old['id']]);}
      if(ctx.mounted)Navigator.pop(ctx);await refresh();
    },child:const Text('Guardar'))]));
  }
  Future<void> deleteIntern(Map<String,Object?> intern) async {
    if(!await confirmDelete('Eliminar practicante','Se eliminará ${intern['name']} y TODO su historial de asistencia. Exporta antes su informe PDF.'))return;
    final db=await AppDatabase.instance;
    await db.transaction((t)async{await t.delete('attendance',where:'intern_id=?',whereArgs:[intern['id']]);await t.delete('interns',where:'id=?',whereArgs:[intern['id']]);});await refresh();
  }
  Future<void> markAttendance(Map<String,Object?> intern,bool entry) async {
    final db=await AppDatabase.instance;
    final today=DateFormat('yyyy-MM-dd').format(DateTime.now());
    final rows=await db.query('attendance',where:'intern_id=? AND work_date=?',whereArgs:[intern['id'],today]);
    if(entry){
      if(rows.isNotEmpty){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Ya se registró la entrada de hoy.')));return;}
      await db.insert('attendance',{'intern_id':intern['id'],'work_date':today,'entry_at':DateTime.now().toIso8601String()});
    }else{
      if(rows.isEmpty||rows.first['exit_at']!=null){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Primero registra una entrada sin salida.')));return;}
      await db.update('attendance',{'exit_at':DateTime.now().toIso8601String()},where:'id=?',whereArgs:[rows.first['id']]);
    }
    await refresh();
  }
  DateTime internFrom=DateTime(DateTime.now().year,DateTime.now().month,1);
  DateTime internTo=DateTime.now();
  Future<void> internReport(Map<String,Object?> intern) async {
    final rows=attendance.where((a)=>a['intern_id']==intern['id']).where((a){final d=DateTime.tryParse('${a['work_date']}');return d!=null&&!d.isBefore(internFrom)&&d.isBefore(internTo.add(const Duration(days:1)));}).toList();
    await ReportService.internExport(business:business,intern:intern,records:rows,start:internFrom,end:internTo);
  }
  Widget internsToolbar()=>Wrap(spacing:10,runSpacing:10,children:[
    FilledButton.icon(onPressed:()=>internDialog(),icon:const Icon(Icons.person_add),label:const Text('Nuevo practicante')),
    OutlinedButton.icon(onPressed:()async{final d=await showDatePicker(context:context,initialDate:internFrom,firstDate:DateTime(2020),lastDate:DateTime(2100));if(d!=null)setState(()=>internFrom=d);},icon:const Icon(Icons.event),label:Text('Desde ${DateFormat('dd/MM/yyyy').format(internFrom)}')),
    OutlinedButton.icon(onPressed:()async{final d=await showDatePicker(context:context,initialDate:internTo,firstDate:DateTime(2020),lastDate:DateTime(2100));if(d!=null)setState(()=>internTo=d);},icon:const Icon(Icons.event),label:Text('Hasta ${DateFormat('dd/MM/yyyy').format(internTo)}')),
  ]);
  Widget internsPage(){
    if(interns.isEmpty)return const Center(child:Text('Aún no hay practicantes registrados.'));
    return ListView.builder(itemCount:interns.length,itemBuilder:(ctx,i){
      final intern=interns[i];final today=DateFormat('yyyy-MM-dd').format(DateTime.now());
      final current=attendance.where((a)=>a['intern_id']==intern['id']&&a['work_date']==today).toList();
      final total=attendance.where((a)=>a['intern_id']==intern['id']&&a['exit_at']!=null).toList();
      final minutes=total.fold<int>(0,(sum,a){final start=DateTime.tryParse('${a['entry_at']}');final end=DateTime.tryParse('${a['exit_at']}');return sum+(start!=null&&end!=null?end.difference(start).inMinutes.clamp(0,1440):0);});
      final hasEntry=current.isNotEmpty;
      final hasExit=hasEntry&&current.first['exit_at']!=null;
      final stateText=hasExit?'Salió hoy':hasEntry?'En curso':'Sin ingreso hoy';
      final stateColor=hasExit?Colors.redAccent:hasEntry?Colors.orange:Colors.grey;
      return Card(child:Padding(padding:const EdgeInsets.all(15),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(children:[const Icon(Icons.school_outlined,color:accent),const SizedBox(width:12),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('${intern['name']}',style:const TextStyle(fontWeight:FontWeight.bold,fontSize:17)),Text('${intern['institution']??''} · ${intern['phone']??''}')]))]),
        const SizedBox(height:8),Text('Días completos: ${total.length}  ·  Horas registradas: ${(minutes/60).toStringAsFixed(2)} h'),
        const SizedBox(height:8),Wrap(spacing:8,runSpacing:8,children:[
          if(hasEntry) Chip(avatar:const Icon(Icons.check_circle,color:Colors.green,size:18),label:const Text('Ingresó hoy'),side:const BorderSide(color:Colors.green)),
          Chip(avatar:Icon(hasExit?Icons.logout:hasEntry?Icons.schedule:Icons.info_outline,color:stateColor,size:18),label:Text(stateText),side:BorderSide(color:stateColor)),
        ]),
        const SizedBox(height:10),Wrap(spacing:8,runSpacing:8,children:[
          FilledButton.icon(onPressed:hasEntry?null:()=>markAttendance(intern,true),style:FilledButton.styleFrom(backgroundColor:Colors.green.shade700,foregroundColor:Colors.white),icon:const Icon(Icons.login),label:const Text('Registrar entrada')),
          FilledButton.icon(onPressed:!hasEntry||hasExit?null:()=>markAttendance(intern,false),style:FilledButton.styleFrom(backgroundColor:Colors.red.shade700,foregroundColor:Colors.white),icon:const Icon(Icons.logout),label:const Text('Registrar salida')),
          OutlinedButton.icon(onPressed:internFrom.isAfter(internTo)?null:()=>internReport(intern),icon:const Icon(Icons.picture_as_pdf),label:const Text('Informe PDF')),
          IconButton(tooltip:'Editar practicante',onPressed:()=>internDialog(intern),icon:const Icon(Icons.edit_outlined)),
          IconButton(tooltip:'Eliminar practicante e historial',onPressed:()=>deleteIntern(intern),icon:const Icon(Icons.delete_outline,color:Colors.redAccent)),
        ])
      ])));
    });
  }
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final month = orders.where((o) { final d = DateTime.tryParse('${o['created_at']}'); return d != null && d.year == now.year && d.month == now.month; }).toList();
    final repaired = month.where((o) => ['Reparado', 'Entregado'].contains(o['status'])).length;
    final pending = orders.where((o) => !['Entregado', 'Cancelado', 'Lista negra'].contains(o['status'])).length;
    final income = payments.where((p){final d=DateTime.tryParse('${p['paid_at']}');return d!=null && d.year==now.year && d.month==now.month;}).fold<double>(0,(a,p)=>a+(p['amount'] as num).toDouble());
    final reportOrders=orders.where((o){final d=DateTime.tryParse('${o['created_at']}');return d!=null && !d.isBefore(reportFrom) && d.isBefore(reportTo.add(const Duration(days:1)));}).toList();
    final reportPayments=payments.where((p){final d=DateTime.tryParse('${p['paid_at']}');return d!=null && !d.isBefore(reportFrom) && d.isBefore(reportTo.add(const Duration(days:1)));}).toList();
    final visible = orders.where((o) {
      if (filter != 'Todos' && o['status'] != filter) return false;
      final registered = DateTime.tryParse('${o['created_at']}');
      if (ordersFrom != null && (registered == null ||
          registered.isBefore(DateTime(ordersFrom!.year, ordersFrom!.month, ordersFrom!.day)))) return false;
      if (ordersTo != null && (registered == null ||
          !registered.isBefore(DateTime(ordersTo!.year, ordersTo!.month, ordersTo!.day).add(const Duration(days: 1))))) return false;
      final text = '${o['id']} ${o['order_no'] ?? ''} ${o['client_name']} ${o['client_phone']} ${o['device_type']} ${o['brand']} ${o['model']} ${o['problem']}'.toLowerCase();
      return text.contains(search.toLowerCase());
    }).toList();
    return Scaffold(body: Row(children: [
      Container(width: 300, decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, border: Border(right: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: .22)))), child: SingleChildScrollView(child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 27, 15, 30), child: Row(children: [ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.asset('assets/images/logo_szr.png', width: 66, height: 66, fit: BoxFit.contain)), const SizedBox(width: 10), const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Servicio Técnico SZR', maxLines: 2, softWrap: true, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)), Text('Gestión de taller', style: TextStyle(fontSize: 11, color: Colors.grey))]))])),
        const Padding(padding: EdgeInsets.fromLTRB(24, 0, 0, 8), child: Align(alignment: Alignment.centerLeft, child: Text('PRINCIPAL', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.5, color: Colors.grey)))),
        nav(0, Icons.space_dashboard_outlined, 'Panel general'), nav(1, Icons.receipt_long_outlined, 'Órdenes de trabajo'), nav(3, Icons.request_quote_outlined, 'Presupuestos'), nav(5, Icons.trending_up, 'Ganancias'),
        const SizedBox(height: 18), const Padding(padding: EdgeInsets.fromLTRB(24, 0, 0, 8), child: Align(alignment: Alignment.centerLeft, child: Text('REGISTROS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.5, color: Colors.grey)))),
        nav(6, Icons.store_outlined, 'Mi negocio'), nav(2, Icons.people_alt_outlined, 'Clientes'), nav(8, Icons.school_outlined, 'Practicantes'), nav(4, Icons.bar_chart_rounded, 'Informe mensual'), nav(7, Icons.archive_outlined, 'Lista negra'),
        const SizedBox(height: 20), navTheme(), const Padding(padding: EdgeInsets.all(18), child: Text('Almacenamiento local · SQLite', style: TextStyle(fontSize: 11, color: Colors.grey))),
      ]))),
      Expanded(child: loading ? const Center(child: CircularProgressIndicator()) : Padding(padding: const EdgeInsets.fromLTRB(30, 27, 30, 18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(['Panel general', 'Órdenes de trabajo', 'Directorio de clientes', 'Presupuestos', 'Informe mensual', 'Ganancias', 'Mi negocio', 'Lista negra', 'Practicantes'][page], style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w800)), const SizedBox(height: 5), Text(['Resumen de la actividad de tu taller', 'Gestiona las reparaciones y actualiza estados rápidamente', 'Historial de personas atendidas', 'Precios, adelantos y saldos por cobrar', 'Resultados por período y PDF', 'Ingresos cobrados y saldos pendientes', 'Personaliza tu taller y su logo', 'Equipos no recogidos', 'Entradas, salidas y reportes de asistencia'][page], style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))])), FilledButton.icon(onPressed: () => orderDialog(), icon: const Icon(Icons.add), label: const Text('Nueva orden'))]),
        const SizedBox(height: 24),
        if (page == 0) ...[
          LayoutBuilder(builder: (ctx, box) => GridView.count(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisCount: box.maxWidth < 850 ? 2 : 4, childAspectRatio: box.maxWidth < 850 ? 3.4 : 1.8, crossAxisSpacing: 12, mainAxisSpacing: 12, children: [
            stat('Ingresados este mes', '${month.length}', Icons.inventory_2_outlined, accent), stat('Reparados este mes', '$repaired', Icons.task_alt, const Color(0xFF35B986)), stat('Órdenes pendientes', '$pending', Icons.pending_actions_outlined, const Color(0xFFE0A33C)), stat('Cobros del mes', money.format(income), Icons.payments_outlined, const Color(0xFFDF7EAE)),
          ])), const SizedBox(height: 25),
          const Text('Accesos rápidos', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)), const SizedBox(height: 12),
          Wrap(spacing: 10, runSpacing: 10, children: [
            OutlinedButton.icon(onPressed: () => setState(() => page = 1), icon: const Icon(Icons.receipt_long_outlined), label: const Text('Todas las órdenes')),
            OutlinedButton.icon(onPressed: () => setState(() => page = 3), icon: const Icon(Icons.payments_outlined), label: const Text('Presupuestos')),
            OutlinedButton.icon(onPressed: () => setState(() => page = 2), icon: const Icon(Icons.people_outline), label: const Text('Clientes')),
            OutlinedButton.icon(onPressed: () => setState(() => page = 4), icon: const Icon(Icons.bar_chart_outlined), label: const Text('Informe mensual')),
          ]), const SizedBox(height: 22),
          Row(children: [const Expanded(child: Text('Órdenes recientes', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700))), TextButton(onPressed: () => setState(() => page = 1), child: const Text('Ver todas'))]), const SizedBox(height: 12),
        ],
        if (page == 1) ...[
          Align(alignment:Alignment.centerRight,child:OutlinedButton.icon(onPressed:deleteAllOrders,icon:const Icon(Icons.delete_forever,color:Colors.redAccent),label:const Text('Eliminar todas las órdenes'))),const SizedBox(height:12),
          Row(children: [Expanded(child: TextField(onChanged: (v) => setState(() => search = v), decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar por cliente, equipo, teléfono o número de orden'))), const SizedBox(width: 12), SizedBox(width: 190, child: DropdownButtonFormField<String>(initialValue: filter, decoration: const InputDecoration(labelText: 'Filtrar por estado'), items: ['Todos', ...statuses].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(), onChanged: (v) => setState(() => filter = v!)))]), const SizedBox(height: 12),
          Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            OutlinedButton.icon(onPressed: () => pickOrdersDate(true),
              icon: const Icon(Icons.date_range),
              label: Text(ordersFrom == null ? 'Desde: todas' : 'Desde: ${DateFormat('dd/MM/yyyy').format(ordersFrom!)}')),
            OutlinedButton.icon(onPressed: () => pickOrdersDate(false),
              icon: const Icon(Icons.event),
              label: Text(ordersTo == null ? 'Hasta: todas' : 'Hasta: ${DateFormat('dd/MM/yyyy').format(ordersTo!)}')),
            TextButton.icon(onPressed: () => setState(() { ordersFrom = null; ordersTo = null; }),
              icon: const Icon(Icons.clear), label: const Text('Limpiar fechas')),
            if (ordersFrom != null && ordersTo != null && ordersFrom!.isAfter(ordersTo!))
              const Text('La fecha inicial debe ser anterior a la final',
                style: TextStyle(color: Colors.redAccent)),
          ]), const SizedBox(height: 18),
        ],
        if (page == 2) ...[
          Row(mainAxisAlignment:MainAxisAlignment.end,children:[OutlinedButton.icon(onPressed:()=>clientDialog(),icon:const Icon(Icons.person_add_alt_1),label:const Text('Nuevo cliente')),const SizedBox(width:10),OutlinedButton.icon(onPressed:deleteAllClients,icon:const Icon(Icons.delete_forever,color:Colors.redAccent),label:const Text('Eliminar todos los clientes'))]),const SizedBox(height:12),
        ],
        if (page == 3) ...[
          Wrap(spacing: 12, runSpacing: 12, children: [
            SizedBox(width: 240, child: stat('Presupuestado', money.format(orders.where((o) => o['status'] != 'Cancelado').fold<double>(0, (v,o) => v + (o['total'] as num).toDouble())), Icons.request_quote_outlined, accent)),
            SizedBox(width: 240, child: stat('Adelantos registrados', money.format(orders.where((o) => o['status'] != 'Cancelado').fold<double>(0, (v,o) => v + (o['paid_total'] as num).toDouble())), Icons.payments_outlined, const Color(0xFF35B986))),
            SizedBox(width: 240, child: stat('Saldos pendientes', money.format(orders.where((o) => o['status'] != 'Cancelado').fold<double>(0, (v,o) => v + (o['total'] as num).toDouble() - (o['paid_total'] as num).toDouble())), Icons.account_balance_wallet_outlined, const Color(0xFFE0A33C))),
          ]), const SizedBox(height: 16),
        ],
        if (page == 4) ...[
          Wrap(spacing:12,runSpacing:10,crossAxisAlignment:WrapCrossAlignment.center,children:[
            OutlinedButton.icon(onPressed:()=>pickReportDate(true),icon:const Icon(Icons.calendar_month),label:Text('Desde: ${DateFormat('dd/MM/yyyy').format(reportFrom)}')),
            OutlinedButton.icon(onPressed:()=>pickReportDate(false),icon:const Icon(Icons.event),label:Text('Hasta: ${DateFormat('dd/MM/yyyy').format(reportTo)}')),
            FilledButton.icon(onPressed:reportFrom.isAfter(reportTo)?null:()async{await ReportService.export(business:business,start:reportFrom,end:reportTo,orders:orders,payments:payments);},icon:const Icon(Icons.picture_as_pdf_outlined),label:const Text('Vista previa / Exportar PDF')),
          ]),const SizedBox(height:15),
          const Text('Resumen del período seleccionado',style:TextStyle(fontSize:18,fontWeight:FontWeight.w700)),const SizedBox(height:14),
          Wrap(spacing: 12, runSpacing: 12, children: [
            SizedBox(width: 220, child: stat('Equipos ingresados', '${reportOrders.length}', Icons.inventory_2_outlined, accent)),
            SizedBox(width: 220, child: stat('Reparados', '${reportOrders.where((o)=>['Reparado','Entregado'].contains(o['status'])).length}', Icons.task_alt_outlined, const Color(0xFF35B986))),
            SizedBox(width: 220, child: stat('Cancelados', '${reportOrders.where((o) => o['status'] == 'Cancelado').length}', Icons.cancel_outlined, const Color(0xFFD06B76))),
            SizedBox(width: 220, child: stat('Ingresos del período', money.format(reportPayments.fold<double>(0,(a,p)=>a+(p['amount'] as num).toDouble())), Icons.payments_outlined, const Color(0xFFE0A33C))),
          ]), const SizedBox(height: 20),
          const Text('Fallas más comunes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)), const SizedBox(height: 10),
        ],
        if(page==8) ...[internsToolbar(),const SizedBox(height:12),],
        if(page==5) ...[
          Wrap(spacing:12,runSpacing:12,children:[
            SizedBox(width:230,child:stat('Adelantos cobrados',money.format(payments.where((p)=>p['kind']=='Adelanto').fold<double>(0,(a,p)=>a+(p['amount'] as num).toDouble())),Icons.payments_outlined,accent)),
            SizedBox(width:230,child:stat('Cobros por entrega',money.format(payments.where((p)=>p['kind']=='Entrega').fold<double>(0,(a,p)=>a+(p['amount'] as num).toDouble())),Icons.local_shipping_outlined,Colors.green)),
            SizedBox(width:230,child:stat('Total cobrado',money.format(payments.fold<double>(0,(a,p)=>a+(p['amount'] as num).toDouble())),Icons.account_balance_wallet_outlined,Colors.blue)),
          ]),const SizedBox(height:14),const Text('Ingresos cobrados (ganancia neta requiere registrar costos)',style:TextStyle(fontSize:12)),const SizedBox(height:14),
        ],
        if(page==6) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if ('${business['logo_path']??''}'.isNotEmpty &&
                        File('${business['logo_path']}').existsSync())
                      Image.file(File('${business['logo_path']}'),
                        height: 110, width: 150, fit: BoxFit.contain),
                    const SizedBox(height: 12),
                    Text('${business['name']??'Mi negocio'}'.toUpperCase(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900,
                        letterSpacing: 1)),
                    const SizedBox(height: 10),
                    Container(width: 110, height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFF32C7F4),
                        borderRadius: BorderRadius.circular(10))),
                    const SizedBox(height: 14),
                    Text('Teléfono: ${business['phone']??''}', textAlign: TextAlign.center),
                    const SizedBox(height: 5),
                    Text('Dirección: ${business['address']??''}', textAlign: TextAlign.center),
                    const SizedBox(height: 18),
                    FilledButton.icon(onPressed: businessDialog,
                      icon: const Icon(Icons.edit),
                      label: const Text('Editar negocio y subir logo')),
                  ],
                )),
                const SizedBox(height: 30),
                Center(child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('COPIAS DE SEGURIDAD', textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                        color: Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFF75D9F7) : const Color(0xFF007C9E))),
                    const SizedBox(height: 10),
                    Container(width: 155, height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFF32C7F4),
                        borderRadius: BorderRadius.circular(10))),
                    const SizedBox(height: 12),
                    Text('Respalda y recupera la información de tu negocio',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 20),
                    Wrap(alignment: WrapAlignment.center, spacing: 12, runSpacing: 12,
                      children: [
                        FilledButton.icon(onPressed: exportBackup,
                          icon: const Icon(Icons.download),
                          label: const Text('Exportar copia ZIP')),
                        OutlinedButton.icon(onPressed: restoreBackup,
                          icon: const Icon(Icons.restore),
                          label: const Text('Restaurar copia ZIP')),
                      ]),
                  ],
                )),
              ],
            ),
          ),
        ],
        Expanded(child: page == 8 ? internsPage() : page == 6 ? const SizedBox.shrink() : page == 7 ? Builder(builder:(ctx){final black=orders.where((o)=>o['status']=='Lista negra').toList();return black.isEmpty?const Center(child:Text('No hay equipos en lista negra.')):ListView.builder(itemCount:black.length,itemBuilder:(ctx,i)=>orderCard(black[i]));}) : page == 5 ? (payments.isEmpty?const Center(child:Text('Aún no hay cobros.')):ListView.builder(itemCount:payments.length,itemBuilder:(ctx,i){final p=payments[i];return Card(child:ListTile(leading:const Icon(Icons.payments_outlined),title:Text('${p['kind']} · Orden #${p['order_id']}'),subtitle:Text('${p['paid_at']}'.split('T').first),trailing:Text(money.format(p['amount']),style:const TextStyle(fontWeight:FontWeight.bold))));})) : page == 4 ? Builder(builder: (ctx) {
          final counts = <String, int>{};
          for (final o in reportOrders) { final issue = '${o['problem']}'.trim(); if (issue.isNotEmpty) counts[issue] = (counts[issue] ?? 0) + 1; }
          final items = counts.entries.toList()..sort((a,b) => b.value.compareTo(a.value));
          if (items.isEmpty) return const Center(child: Text('No hay fallas registradas este mes.'));
          return ListView.builder(itemCount: items.length, itemBuilder: (ctx,i) => Card(child: ListTile(title: Text(items[i].key), trailing: Text('${items[i].value} caso(s)', style: const TextStyle(fontWeight: FontWeight.bold)))));
        }) : page == 2 ? (clients.isEmpty ? const Center(child: Text('Todavía no hay clientes. Se registrarán al crear órdenes.')) : ListView.builder(itemCount: clients.length, itemBuilder: (ctx, i) { final c = clients[i]; final count = orders.where((o) => o['client_id'] == c['id']).length; return Card(child: ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7), leading: CircleAvatar(backgroundColor: accent.withValues(alpha: .14), child: const Icon(Icons.person_outline, color: accent)), title: Text('${c['name']}', style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: Text('${c['phone']}  ·  $count orden(es)'), trailing: Row(mainAxisSize:MainAxisSize.min,children:[IconButton(tooltip:'Editar cliente',onPressed:()=>clientDialog(c),icon:const Icon(Icons.edit_outlined)),IconButton(tooltip:'Eliminar cliente',onPressed:()=>deleteClient(c),icon:const Icon(Icons.delete_outline,color:Colors.redAccent))]))); }))
          : (page == 0 ? orders.take(6).toList() : page == 3 ? orders.where((o) => o['status'] != 'Cancelado').toList() : visible).isEmpty ? Center(child: Text(page == 1 ? 'No se encontraron órdenes.' : 'Todavía no hay órdenes registradas.')) : ListView.builder(itemCount: page == 0 ? orders.take(6).length : page == 3 ? orders.where((o) => o['status'] != 'Cancelado').length : visible.length, itemBuilder: (ctx, i) => orderCard(page == 0 ? orders[i] : page == 3 ? orders.where((o) => o['status'] != 'Cancelado').toList()[i] : visible[i]))),
      ]))),
    ]));
  }
  Widget navTheme() => ListTile(leading: Icon(widget.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined), title: Text(widget.isDark ? 'Cambiar a modo claro' : 'Cambiar a modo oscuro', style: const TextStyle(fontSize: 13)), onTap: widget.onToggleTheme);
}
