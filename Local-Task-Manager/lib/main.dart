import 'package:flutter/foundation.dart'; // For kIsWeb
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

void main() {
  runApp(const TaskManagerApp());
}

// ==========================================
// 1. DATABASE HELPER (Web-Safe & Mobile SQLite)
// ==========================================
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  // Fallback list for web browser preview in FlutLab
  final List<Map<String, Object?>> _webMemoryStorage = [];
  int _webIdCounter = 1;

  DatabaseHelper._init();

  Future<Database?> get database async {
    if (kIsWeb) return null; // Bypass real SQLite on web browser preview
    if (_database != null) return _database!;
    _database = await _initDB('tasks.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE tasks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        is_completed INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  Future<int> addTask(String title) async {
    if (kIsWeb) {
      // Web preview fallback simulation
      _webMemoryStorage.insert(0, {
        'id': _webIdCounter++,
        'title': title,
        'is_completed': 0,
      });
      return 1;
    }

    final db = await instance.database;
    return await db!.insert('tasks', {'title': title, 'is_completed': 0});
  }

  Future<List<Map<String, Object?>>> getTasks() async {
    if (kIsWeb) {
      return List.from(_webMemoryStorage);
    }

    final db = await instance.database;
    return await db!.query('tasks', orderBy: 'id DESC');
  }

  Future<int> updateTaskCompletion(int id, int isCompleted) async {
    if (kIsWeb) {
      final index = _webMemoryStorage.indexWhere((task) => task['id'] == id);
      if (index != -1) {
        _webMemoryStorage[index]['is_completed'] = isCompleted;
      }
      return 1;
    }

    final db = await instance.database;
    return await db!.update(
      'tasks',
      {'is_completed': isCompleted},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteTask(int id) async {
    if (kIsWeb) {
      _webMemoryStorage.removeWhere((task) => task['id'] == id);
      return 1;
    }

    final db = await instance.database;
    return await db!.delete(
      'tasks',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}

// ==========================================
// 2. REPOSITORY PATTERN
// ==========================================
class TaskRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<int> create(String title) async {
    return await _dbHelper.addTask(title);
  }

  Future<List<Map<String, Object?>>> getAll() async {
    return await _dbHelper.getTasks();
  }

  Future<int> markCompleted(int id, bool isCompleted) async {
    return await _dbHelper.updateTaskCompletion(id, isCompleted ? 1 : 0);
  }

  Future<int> delete(int id) async {
    return await _dbHelper.deleteTask(id);
  }
}

// ==========================================
// 3. FLUTTER USER INTERFACE
// ==========================================
class TaskManagerApp extends StatelessWidget {
  const TaskManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Local Task Manager',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const TaskScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class TaskScreen extends StatefulWidget {
  const TaskScreen({super.key});

  @override
  State<TaskScreen> createState() => _TaskScreenState();
}

class _TaskScreenState extends State<TaskScreen> {
  final TaskRepository _repository = TaskRepository();
  final TextEditingController _controller = TextEditingController();
  List<Map<String, Object?>> _tasks = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    setState(() => _isLoading = true);
    try {
      final tasks = await _repository.getAll();
      setState(() {
        _tasks = tasks;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnackBar('Error loading tasks: $e');
    }
  }

  Future<void> _addTask() async {
    final title = _controller.text.trim();
    if (title.isEmpty) {
      _showSnackBar('Task title cannot be empty or whitespace.');
      return;
    }

    try {
      await _repository.create(title);
      _controller.clear();
      await _loadTasks();
    } catch (e) {
      _showSnackBar('Failed to add task: $e');
    }
  }

  Future<void> _toggleTaskCompletion(int id, int currentStatus) async {
    try {
      final newStatus = currentStatus != 1;
      await _repository.markCompleted(id, newStatus);
      await _loadTasks();
    } catch (e) {
      _showSnackBar('Failed to update task: $e');
    }
  }

  Future<void> _deleteTask(int id) async {
    try {
      await _repository.delete(id);
      await _loadTasks();
    } catch (e) {
      _showSnackBar('Failed to delete task: $e');
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Local SQLite Task Manager'),
        centerTitle: true,
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // TextField for task title
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: 'Task Title',
                hintText: 'e.g., Complete IT 126 Activity',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _addTask(),
            ),
            const SizedBox(height: 12),
            // Add Task button placed right below the text field, spanning width
            ElevatedButton(
              onPressed: _addTask,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text(
                'Add Task',
                style: TextStyle(fontSize: 16),
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _tasks.isEmpty
                      ? const Center(
                          child: Text(
                            'No tasks saved yet. Add one above!',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _tasks.length,
                          itemBuilder: (context, index) {
                            final task = _tasks[index];
                            final id = task['id'] as int;
                            final title = task['title'] as String;
                            final isCompleted =
                                (task['is_completed'] as int) == 1;

                            return Card(
                              elevation: 2,
                              margin: const EdgeInsets.symmetric(vertical: 6),
                              child: ListTile(
                                leading: Checkbox(
                                  value: isCompleted,
                                  activeColor: Colors.blue,
                                  onChanged: (_) => _toggleTaskCompletion(
                                    id,
                                    task['is_completed'] as int,
                                  ),
                                ),
                                title: Text(
                                  title,
                                  style: TextStyle(
                                    decoration: isCompleted
                                        ? TextDecoration.lineThrough
                                        : null,
                                    color: isCompleted
                                        ? Colors.grey
                                        : Colors.black87,
                                  ),
                                ),
                                trailing: IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: Colors.redAccent,
                                  ),
                                  onPressed: () => _deleteTask(id),
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
