import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class AppDatabase {
  static Future<void> close() async {await _db?.close();_db=null;}
  static Database? _db;
  static Future<Database> get instance async {
    if (_db != null) return _db!;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final base = await getApplicationSupportDirectory();
    final folder = Directory(p.join(base.path, 'ServicioTecnicoPro'));
    await folder.create(recursive: true);
    _db = await openDatabase(p.join(folder.path, 'servicio_tecnico.db'), version: 5,
      onCreate: (db, version) async {
        await db.execute('''CREATE TABLE clients (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL, phone TEXT NOT NULL,
          email TEXT, document TEXT, created_at TEXT NOT NULL)''');
        await db.execute('''CREATE TABLE orders (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          client_id INTEGER NOT NULL,
          order_no INTEGER UNIQUE,
          device_type TEXT NOT NULL, brand TEXT, model TEXT NOT NULL,
          serial TEXT, problem TEXT NOT NULL, work TEXT,
          notes TEXT, status TEXT NOT NULL,
          total REAL NOT NULL DEFAULT 0,
          advance REAL NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL, received_by TEXT, received_by_type TEXT, delivery_at TEXT,
          FOREIGN KEY(client_id) REFERENCES clients(id))''');
        await db.execute('CREATE TABLE payments (id INTEGER PRIMARY KEY AUTOINCREMENT, order_id INTEGER NOT NULL, amount REAL NOT NULL, kind TEXT NOT NULL, paid_at TEXT NOT NULL)');
        await db.execute('CREATE TABLE business (id INTEGER PRIMARY KEY CHECK(id=1), name TEXT NOT NULL, owner TEXT, phone TEXT, address TEXT, email TEXT, ruc TEXT, logo_path TEXT)');
        await db.execute('CREATE TABLE blacklist (order_id INTEGER PRIMARY KEY, reason TEXT NOT NULL, added_at TEXT NOT NULL)');
        await db.execute('CREATE TABLE interns (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, institution TEXT, phone TEXT, created_at TEXT NOT NULL)');
        await db.execute('CREATE TABLE attendance (id INTEGER PRIMARY KEY AUTOINCREMENT, intern_id INTEGER NOT NULL, work_date TEXT NOT NULL, entry_at TEXT NOT NULL, exit_at TEXT, UNIQUE(intern_id,work_date))');
      }, onUpgrade: (db, old, next) async {
        if (old < 2) {
          await db.execute('CREATE TABLE IF NOT EXISTS payments (id INTEGER PRIMARY KEY AUTOINCREMENT, order_id INTEGER NOT NULL, amount REAL NOT NULL, kind TEXT NOT NULL, paid_at TEXT NOT NULL)');
          await db.execute('CREATE TABLE IF NOT EXISTS business (id INTEGER PRIMARY KEY CHECK(id=1), name TEXT NOT NULL, owner TEXT, phone TEXT, address TEXT, email TEXT, ruc TEXT, logo_path TEXT)');
          await db.execute('CREATE TABLE IF NOT EXISTS blacklist (order_id INTEGER PRIMARY KEY, reason TEXT NOT NULL, added_at TEXT NOT NULL)');
          final oldOrders = await db.query('orders');
          for (final o in oldOrders) {
            final a = (o['advance'] as num?)?.toDouble() ?? 0;
            if (a > 0) await db.insert('payments', {'order_id':o['id'], 'amount':a, 'kind':'Adelanto', 'paid_at':o['created_at']});
          }
        }
        if(old<3){
          await db.execute('CREATE TABLE IF NOT EXISTS interns (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, institution TEXT, phone TEXT, created_at TEXT NOT NULL)');
          await db.execute('CREATE TABLE IF NOT EXISTS attendance (id INTEGER PRIMARY KEY AUTOINCREMENT, intern_id INTEGER NOT NULL, work_date TEXT NOT NULL, entry_at TEXT NOT NULL, exit_at TEXT, UNIQUE(intern_id,work_date))');
        }
        if (old < 4) {
          await db.execute('ALTER TABLE orders ADD COLUMN received_by TEXT');
          await db.execute('ALTER TABLE orders ADD COLUMN received_by_type TEXT');
        }
        if (old < 5) {
          await db.execute('ALTER TABLE orders ADD COLUMN order_no INTEGER');
          await db.execute('UPDATE orders SET order_no = id WHERE order_no IS NULL');
          await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_orders_order_no ON orders(order_no)');
        }
      });
    return _db!;
  }
}
