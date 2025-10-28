import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path_package;
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:excel/excel.dart' as excel_lib;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  runApp(const CashBookApp());
}

class CashBookApp extends StatelessWidget {
  const CashBookApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cash Book',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: const DashboardScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// ============================================================================
// MODELS
// ============================================================================

class TransactionModel {
  final int? id;
  final String type; // 'income' or 'expense'
  final double amount;
  final String category;
  final String description;
  final DateTime date;

  TransactionModel({
    this.id,
    required this.type,
    required this.amount,
    required this.category,
    required this.description,
    required this.date,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type,
      'amount': amount,
      'category': category,
      'description': description,
      'date': date.toIso8601String(),
    };
  }

  factory TransactionModel.fromMap(Map<String, dynamic> map) {
    return TransactionModel(
      id: map['id'],
      type: map['type'],
      amount: map['amount'],
      category: map['category'],
      description: map['description'],
      date: DateTime.parse(map['date']),
    );
  }
}

class CategoryModel {
  final int? id;
  final String name;
  final String type; // 'income' or 'expense'
  final IconData icon;
  final Color color;

  CategoryModel({
    this.id,
    required this.name,
    required this.type,
    required this.icon,
    required this.color,
  });
}

// ============================================================================
// DATABASE SERVICE
// ============================================================================

class DatabaseService {
  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await initDB();
    return _database!;
  }

  Future<Database> initDB() async {
    String path = path_package.join(await getDatabasesPath(), 'cashbook.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE transactions(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            type TEXT NOT NULL,
            amount REAL NOT NULL,
            category TEXT NOT NULL,
            description TEXT,
            date TEXT NOT NULL
          )
        ''');
      },
    );
  }

  Future<int> insertTransaction(TransactionModel transaction) async {
    final db = await database;
    return await db.insert('transactions', transaction.toMap());
  }

  Future<List<TransactionModel>> getTransactions() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'transactions',
      orderBy: 'date DESC',
    );
    return List.generate(maps.length, (i) => TransactionModel.fromMap(maps[i]));
  }

  Future<int> deleteTransaction(int id) async {
    final db = await database;
    return await db.delete('transactions', where: 'id = ?', whereArgs: [id]);
  }

  // Update an existing transaction
  Future<int> updateTransaction(TransactionModel transaction) async {
    final db = await database;
    return await db.update(
      'transactions',
      transaction.toMap(),
      where: 'id = ?',
      whereArgs: [transaction.id],
    );
  }

  Future<Map<String, double>> getSummary() async {
    final db = await database;
    final income = await db.rawQuery(
      'SELECT SUM(amount) as total FROM transactions WHERE type = ?',
      ['income'],
    );
    final expense = await db.rawQuery(
      'SELECT SUM(amount) as total FROM transactions WHERE type = ?',
      ['expense'],
    );

    double totalIncome = income.first['total'] as double? ?? 0.0;
    double totalExpense = expense.first['total'] as double? ?? 0.0;

    return {
      'income': totalIncome,
      'expense': totalExpense,
      'balance': totalIncome - totalExpense,
    };
  }
}

// ============================================================================
// DASHBOARD SCREEN
// ============================================================================

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final DatabaseService _dbService = DatabaseService();
  Map<String, double> summary = {'income': 0, 'expense': 0, 'balance': 0};
  List<TransactionModel> recentTransactions = [];
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final sum = await _dbService.getSummary();
    final trans = await _dbService.getTransactions();
    setState(() {
      summary = sum;
      recentTransactions = trans.take(5).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      _buildDashboard(),
      const TransactionsScreen(),
      const ReportsScreen(),
      const CategoryAnalyticsScreen(), // Changed from ProductAnalyticsScreen
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Cash Book'), elevation: 0),
      body: screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.list),
            label: 'Transactions',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart),
            label: 'Reports',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.category),
            label: 'Categories',
          ), // Changed icon and label
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const AddTransactionScreen(),
            ),
          );
          _loadData();
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildDashboard() {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSummaryCards(),
              const SizedBox(height: 24),
              _buildChartSection(),
              const SizedBox(height: 24),
              const Text(
                'Recent Transactions',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              _buildRecentTransactions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCards() {
    return Column(
      children: [
        _summaryCard(
          'Cash Balance',
          summary['balance']!,
          Colors.blue,
          Icons.account_balance_wallet,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _summaryCard(
                'Income',
                summary['income']!,
                Colors.green,
                Icons.arrow_upward,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _summaryCard(
                'Expense',
                summary['expense']!,
                Colors.red,
                Icons.arrow_downward,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _summaryCard(String title, double amount, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: Colors.white),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(color: Colors.grey[700], fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  '₹${amount.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: color,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartSection() {
    return Container(
      height: 200,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 5,
          ),
        ],
      ),
      child: PieChart(
        PieChartData(
          sections: [
            PieChartSectionData(
              value: summary['income']!,
              color: Colors.green,
              title: 'Income',
              radius: 50,
              titleStyle: const TextStyle(color: Colors.white, fontSize: 12),
            ),
            PieChartSectionData(
              value: summary['expense']!,
              color: Colors.red,
              title: 'Expense',
              radius: 50,
              titleStyle: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ],
          sectionsSpace: 2,
          centerSpaceRadius: 40,
        ),
      ),
    );
  }

  Widget _buildRecentTransactions() {
    if (recentTransactions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Text(
            'No transactions yet',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: recentTransactions.length,
      itemBuilder: (context, index) {
        final trans = recentTransactions[index];
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor:
                  trans.type == 'income'
                      ? Colors.green.withOpacity(0.2)
                      : Colors.red.withOpacity(0.2),
              child: Icon(
                trans.type == 'income' ? Icons.add : Icons.remove,
                color: trans.type == 'income' ? Colors.green : Colors.red,
              ),
            ),
            title: Text(trans.category),
            subtitle: Text(trans.description),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '₹${trans.amount.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: trans.type == 'income' ? Colors.green : Colors.red,
                  ),
                ),
                Text(
                  DateFormat('dd/MM/yy').format(trans.date),
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ============================================================================
// ADD TRANSACTION SCREEN (PRODUCT FIELD REMOVED)
// ============================================================================

class AddTransactionScreen extends StatefulWidget {
  final TransactionModel? transaction;
  const AddTransactionScreen({Key? key, this.transaction}) : super(key: key);

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _descController = TextEditingController();
  final DatabaseService _dbService = DatabaseService();

  String _type = 'income';
  String _category = 'Sales';
  DateTime _selectedDate = DateTime.now();
  bool get isEditing => widget.transaction != null;

  List<String> incomeCategories = [
    'Sales',
    'Service',
    'Investment',
    'Add Custom Category...',
  ];
  List<String> expenseCategories = [
    'Rent',
    'Salary',
    'Fuel',
    'Utilities',
    'Supplies',
    'Add Custom Category...',
  ];

  final List<String> customIncomeCategories = [];
  final List<String> customExpenseCategories = [];

  @override
  void initState() {
    super.initState();
    final t = widget.transaction;
    if (t != null) {
      _type = t.type;
      _category = t.category;
      _selectedDate = t.date;
      _amountController.text = t.amount.toStringAsFixed(2);
      _descController.text = t.description;
      // if category is not in default lists, add to custom lists so dropdown can show it
      if (_type == 'income' && !incomeCategories.contains(_category)) {
        customIncomeCategories.add(_category);
      } else if (_type == 'expense' && !expenseCategories.contains(_category)) {
        customExpenseCategories.add(_category);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Transaction')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Transaction Type',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('Income'),
                      selected: _type == 'income',
                      onSelected: (selected) {
                        setState(() {
                          _type = 'income';
                          _category = incomeCategories.first;
                        });
                      },
                      selectedColor: Colors.green.withOpacity(0.3),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('Expense'),
                      selected: _type == 'expense',
                      onSelected: (selected) {
                        setState(() {
                          _type = 'expense';
                          _category = expenseCategories.first;
                        });
                      },
                      selectedColor: Colors.red.withOpacity(0.3),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              DropdownButtonFormField<String>(
                value: _category,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  border: OutlineInputBorder(),
                ),
                items:
                    (_type == 'income'
                            ? [...incomeCategories, ...customIncomeCategories]
                            : [
                              ...expenseCategories,
                              ...customExpenseCategories,
                            ])
                        .map(
                          (cat) =>
                              DropdownMenuItem(value: cat, child: Text(cat)),
                        )
                        .toList(),
                onChanged: (value) async {
                  if (value == 'Add Custom Category...') {
                    await _showAddCategoryDialog();
                  } else {
                    setState(() => _category = value!);
                  }
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _amountController,
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  border: OutlineInputBorder(),
                  prefixText: '₹ ',
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter amount';
                  }
                  if (double.tryParse(value) == null) {
                    return 'Please enter valid amount';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descController,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: _selectedDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                  );
                  if (date != null && mounted) {
                    setState(() => _selectedDate = date);
                  }
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Date',
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.calendar_today),
                  ),
                  child: Text(DateFormat('dd MMM yyyy').format(_selectedDate)),
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _saveTransaction,
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        _type == 'income' ? Colors.green : Colors.red,
                  ),
                  child: Text(
                    isEditing ? 'Update Transaction' : 'Save Transaction',
                    style: const TextStyle(fontSize: 16, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveTransaction() async {
    if (_formKey.currentState!.validate()) {
      final transaction = TransactionModel(
        id: widget.transaction?.id,
        type: _type,
        amount: double.parse(_amountController.text),
        category: _category,
        description: _descController.text,
        date: _selectedDate,
      );

      if (isEditing) {
        await _dbService.updateTransaction(transaction);
      } else {
        await _dbService.insertTransaction(transaction);
      }

      if (mounted) Navigator.pop(context, true);
    }
  }

  Future<void> _showAddCategoryDialog() async {
    final TextEditingController categoryController = TextEditingController();

    return showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(
            'Add ${_type == 'income' ? 'Income' : 'Expense'} Category',
          ),
          content: TextField(
            controller: categoryController,
            decoration: const InputDecoration(
              labelText: 'Category Name',
              hintText: 'Enter category name',
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.words,
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final newCategory = categoryController.text.trim();
                if (newCategory.isNotEmpty) {
                  setState(() {
                    if (_type == 'income') {
                      customIncomeCategories.add(newCategory);
                      _category = newCategory;
                    } else {
                      customExpenseCategories.add(newCategory);
                      _category = newCategory;
                    }
                  });
                  Navigator.of(dialogContext).pop();
                }
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descController.dispose();
    super.dispose();
  }
}

// ============================================================================
// TRANSACTIONS SCREEN
// ============================================================================

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({Key? key}) : super(key: key);

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  final DatabaseService _dbService = DatabaseService();
  List<TransactionModel> transactions = [];
  List<TransactionModel> filteredTransactions = [];
  String searchQuery = '';
  String selectedFilter = 'All';
  String viewMode = 'List';

  @override
  void initState() {
    super.initState();
    _loadTransactions();
  }

  Future<void> _loadTransactions() async {
    final trans = await _dbService.getTransactions();
    setState(() {
      transactions = trans;
      _applyFilters();
    });
  }

  void _applyFilters() {
    List<TransactionModel> filtered = List.from(transactions);

    if (viewMode == 'List') {
      final now = DateTime.now();
      switch (selectedFilter) {
        case 'This Week':
          final weekAgo = now.subtract(const Duration(days: 7));
          filtered = filtered.where((t) => t.date.isAfter(weekAgo)).toList();
          break;
        case 'This Month':
          final monthAgo = DateTime(now.year, now.month - 1, now.day);
          filtered = filtered.where((t) => t.date.isAfter(monthAgo)).toList();
          break;
        case 'This Year':
          final yearAgo = DateTime(now.year - 1, now.month, now.day);
          filtered = filtered.where((t) => t.date.isAfter(yearAgo)).toList();
          break;
        case 'All':
        default:
          break;
      }
    }

    if (searchQuery.isNotEmpty) {
      filtered =
          filtered.where((t) {
            return t.category.toLowerCase().contains(
                  searchQuery.toLowerCase(),
                ) ||
                t.description.toLowerCase().contains(searchQuery.toLowerCase());
          }).toList();
    }

    setState(() {
      filteredTransactions = filtered;
    });
  }

  void _filterTransactions(String query) {
    searchQuery = query;
    _applyFilters();
  }

  void _changeDateFilter(String filter) {
    setState(() {
      selectedFilter = filter;
    });
    _applyFilters();
  }

  Map<String, List<TransactionModel>> _groupTransactionsByWeek() {
    Map<String, List<TransactionModel>> grouped = {};

    for (var trans in filteredTransactions) {
      final weekStart = _getWeekStart(trans.date);
      final weekEnd = weekStart.add(const Duration(days: 6));
      final weekKey =
          '${DateFormat('dd MMM').format(weekStart)} - ${DateFormat('dd MMM yyyy').format(weekEnd)}';

      if (!grouped.containsKey(weekKey)) {
        grouped[weekKey] = [];
      }
      grouped[weekKey]!.add(trans);
    }

    return grouped;
  }

  Map<String, List<TransactionModel>> _groupTransactionsByMonth() {
    Map<String, List<TransactionModel>> grouped = {};

    for (var trans in filteredTransactions) {
      final monthKey = DateFormat('MMMM yyyy').format(trans.date);

      if (!grouped.containsKey(monthKey)) {
        grouped[monthKey] = [];
      }
      grouped[monthKey]!.add(trans);
    }

    return grouped;
  }

  Map<String, List<TransactionModel>> _groupTransactionsByYear() {
    Map<String, List<TransactionModel>> grouped = {};

    for (var trans in filteredTransactions) {
      final yearKey = DateFormat('yyyy').format(trans.date);

      if (!grouped.containsKey(yearKey)) {
        grouped[yearKey] = [];
      }
      grouped[yearKey]!.add(trans);
    }

    return grouped;
  }

  DateTime _getWeekStart(DateTime date) {
    return date.subtract(Duration(days: date.weekday - 1));
  }

  double _calculateGroupTotal(
    List<TransactionModel> transactions,
    String type,
  ) {
    return transactions
        .where((t) => t.type == type)
        .fold(0.0, (sum, t) => sum + t.amount);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                decoration: InputDecoration(
                  hintText: 'Search transactions...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onChanged: _filterTransactions,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'List',
                          label: Text('List View'),
                          icon: Icon(Icons.list),
                        ),
                        ButtonSegment(
                          value: 'Grouped',
                          label: Text('Grouped'),
                          icon: Icon(Icons.calendar_view_month),
                        ),
                      ],
                      selected: {viewMode},
                      onSelectionChanged: (Set<String> newSelection) {
                        setState(() {
                          viewMode = newSelection.first;
                          if (viewMode == 'Grouped') {
                            selectedFilter = 'Month';
                          } else {
                            selectedFilter = 'All';
                          }
                        });
                        _applyFilters();
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children:
                      viewMode == 'List'
                          ? [
                            _buildFilterChip('All'),
                            const SizedBox(width: 8),
                            _buildFilterChip('This Week'),
                            const SizedBox(width: 8),
                            _buildFilterChip('This Month'),
                            const SizedBox(width: 8),
                            _buildFilterChip('This Year'),
                          ]
                          : [
                            _buildFilterChip('Week'),
                            const SizedBox(width: 8),
                            _buildFilterChip('Month'),
                            const SizedBox(width: 8),
                            _buildFilterChip('Year'),
                          ],
                ),
              ),
            ],
          ),
        ),
        if (filteredTransactions.isNotEmpty)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildSummaryItem(
                  'Income',
                  _calculateTotal('income'),
                  Colors.green,
                ),
                _buildSummaryItem(
                  'Expense',
                  _calculateTotal('expense'),
                  Colors.red,
                ),
                _buildSummaryItem(
                  'Balance',
                  _calculateTotal('income') - _calculateTotal('expense'),
                  Colors.blue,
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        Expanded(
          child:
              filteredTransactions.isEmpty
                  ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.inbox_outlined,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No transactions found',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  )
                  : viewMode == 'List'
                  ? _buildListView()
                  : _buildGroupedView(),
        ),
      ],
    );
  }

  Widget _buildListView() {
    return ListView.builder(
      itemCount: filteredTransactions.length,
      itemBuilder: (context, index) {
        final trans = filteredTransactions[index];
        return _buildTransactionCard(trans);
      },
    );
  }

  Widget _buildGroupedView() {
    Map<String, List<TransactionModel>> groupedData;

    switch (selectedFilter) {
      case 'Week':
        groupedData = _groupTransactionsByWeek();
        break;
      case 'Year':
        groupedData = _groupTransactionsByYear();
        break;
      case 'Month':
      default:
        groupedData = _groupTransactionsByMonth();
        break;
    }

    final sortedKeys =
        groupedData.keys.toList()..sort((a, b) => b.compareTo(a));

    if (sortedKeys.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.calendar_today_outlined,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No ${selectedFilter.toLowerCase()}s with transactions',
              style: TextStyle(color: Colors.grey[600], fontSize: 16),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: sortedKeys.length,
      itemBuilder: (context, index) {
        final groupKey = sortedKeys[index];
        final groupTransactions = groupedData[groupKey]!;
        final income = _calculateGroupTotal(groupTransactions, 'income');
        final expense = _calculateGroupTotal(groupTransactions, 'expense');
        final balance = income - expense;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          elevation: 2,
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            childrenPadding: EdgeInsets.zero,
            title: Row(
              children: [
                Icon(
                  selectedFilter == 'Week'
                      ? Icons.calendar_view_week
                      : selectedFilter == 'Month'
                      ? Icons.calendar_view_month
                      : Icons.calendar_today,
                  color: Colors.blue,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    groupKey,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${groupTransactions.length} transaction${groupTransactions.length > 1 ? 's' : ''}',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '₹${balance.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: balance >= 0 ? Colors.green : Colors.red,
                  ),
                ),
                Text(
                  'Net',
                  style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                ),
              ],
            ),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  border: Border(
                    top: BorderSide(color: Colors.grey[300]!),
                    bottom: BorderSide(color: Colors.grey[300]!),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          Icon(
                            Icons.arrow_upward,
                            color: Colors.green,
                            size: 20,
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Income',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '₹${income.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(width: 1, height: 50, color: Colors.grey[300]),
                    Expanded(
                      child: Column(
                        children: [
                          Icon(
                            Icons.arrow_downward,
                            color: Colors.red,
                            size: 20,
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Expense',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '₹${expense.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.red,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              ...groupTransactions.map(
                (trans) => _buildTransactionCard(trans, compact: true),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTransactionCard(TransactionModel trans, {bool compact = false}) {
    return ListTile(
      contentPadding: EdgeInsets.symmetric(
        horizontal: compact ? 32 : 16,
        vertical: 8,
      ),
      leading: CircleAvatar(
        backgroundColor:
            trans.type == 'income'
                ? Colors.green.withOpacity(0.2)
                : Colors.red.withOpacity(0.2),
        child: Icon(
          trans.type == 'income' ? Icons.add : Icons.remove,
          color: trans.type == 'income' ? Colors.green : Colors.red,
        ),
      ),
      title: Text(trans.category),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (trans.description.isNotEmpty) Text(trans.description),
          Text(
            DateFormat('dd MMM yyyy, hh:mm a').format(trans.date),
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '₹${trans.amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: trans.type == 'income' ? Colors.green : Colors.red,
            ),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'edit') {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (context) => AddTransactionScreen(transaction: trans),
                  ),
                );
                _loadTransactions();
              } else if (value == 'delete') {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder:
                      (dialogContext) => AlertDialog(
                        title: const Text('Confirm delete'),
                        content: const Text(
                          'Are you sure you want to delete this transaction?',
                        ),
                        actions: [
                          TextButton(
                            onPressed:
                                () => Navigator.of(dialogContext).pop(false),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            onPressed:
                                () => Navigator.of(dialogContext).pop(true),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                );
                if (confirmed == true) {
                  await _dbService.deleteTransaction(trans.id!);
                  _loadTransactions();
                }
              }
            },
            itemBuilder:
                (context) => [
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label) {
    final isSelected = selectedFilter == label;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          _changeDateFilter(label);
        }
      },
      selectedColor: Colors.blue.withOpacity(0.3),
      checkmarkColor: Colors.blue,
      backgroundColor: Colors.grey[200],
    );
  }

  Widget _buildSummaryItem(String label, double amount, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[700],
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '₹${amount.toStringAsFixed(2)}',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  double _calculateTotal(String type) {
    return filteredTransactions
        .where((t) => t.type == type)
        .fold(0.0, (sum, t) => sum + t.amount);
  }
}

// ============================================================================
// REPORTS SCREEN
// ============================================================================

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({Key? key}) : super(key: key);

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final DatabaseService _dbService = DatabaseService();
  Map<String, double> summary = {};
  List<TransactionModel> allTransactions = [];
  bool isExporting = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final sum = await _dbService.getSummary();
    final trans = await _dbService.getTransactions();
    setState(() {
      summary = sum;
      allTransactions = trans;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Financial Summary',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          _buildReportCard(
            'Total Income',
            summary['income'] ?? 0,
            Colors.green,
          ),
          const SizedBox(height: 12),
          _buildReportCard(
            'Total Expense',
            summary['expense'] ?? 0,
            Colors.red,
          ),
          const SizedBox(height: 12),
          _buildReportCard('Net Balance', summary['balance'] ?? 0, Colors.blue),
          const SizedBox(height: 32),
          if (isExporting)
            const Center(child: CircularProgressIndicator())
          else ...[
            const Text(
              'Export Options',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildExportButton(
              'Export as PDF',
              Icons.picture_as_pdf,
              _exportAsPDF,
            ),
            _buildExportButton(
              'Export as Excel',
              Icons.table_chart,
              _exportAsExcel,
            ),
            _buildExportButton(
              'Export as CSV',
              Icons.file_present,
              _exportAsCSV,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReportCard(String title, double amount, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
          ),
          Text(
            '₹${amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExportButton(String text, IconData icon, Function() onPressed) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(text),
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(double.infinity, 50),
        ),
      ),
    );
  }

  Future<void> _exportAsPDF() async {
    setState(() => isExporting = true);
    try {
      final pdf = pw.Document();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context pdfContext) {
            return [
              pw.Header(
                level: 0,
                child: pw.Text(
                  'Cash Book Report',
                  style: pw.TextStyle(
                    fontSize: 24,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.SizedBox(height: 20),

              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: const pw.BorderRadius.all(
                    pw.Radius.circular(5),
                  ),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Financial Summary',
                      style: pw.TextStyle(
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 10),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          'Total Income:',
                          style: const pw.TextStyle(fontSize: 14),
                        ),
                        pw.Text(
                          '₹${summary['income']?.toStringAsFixed(2) ?? '0.00'}',
                          style: pw.TextStyle(
                            fontSize: 14,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 5),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          'Total Expense:',
                          style: const pw.TextStyle(fontSize: 14),
                        ),
                        pw.Text(
                          '₹${summary['expense']?.toStringAsFixed(2) ?? '0.00'}',
                          style: pw.TextStyle(
                            fontSize: 14,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 5),
                    pw.Divider(),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          'Net Balance:',
                          style: pw.TextStyle(
                            fontSize: 16,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.Text(
                          '₹${summary['balance']?.toStringAsFixed(2) ?? '0.00'}',
                          style: pw.TextStyle(
                            fontSize: 16,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 30),

              pw.Text(
                'All Transactions',
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 10),
              pw.Table.fromTextArray(
                headers: ['Date', 'Type', 'Category', 'Description', 'Amount'],
                data:
                    allTransactions
                        .map(
                          (t) => [
                            DateFormat('dd/MM/yyyy').format(t.date),
                            t.type.toUpperCase(),
                            t.category,
                            t.description.isEmpty ? '-' : t.description,
                            '₹${t.amount.toStringAsFixed(2)}',
                          ],
                        )
                        .toList(),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.grey300,
                ),
                cellHeight: 30,
                cellAlignments: {
                  0: pw.Alignment.centerLeft,
                  1: pw.Alignment.center,
                  2: pw.Alignment.centerLeft,
                  3: pw.Alignment.centerLeft,
                  4: pw.Alignment.centerRight,
                },
              ),
            ];
          },
        ),
      );

      await Printing.sharePdf(
        bytes: await pdf.save(),
        filename:
            'cashbook_report_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PDF exported successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error exporting PDF: $e')));
      }
    } finally {
      setState(() => isExporting = false);
    }
  }

  Future<void> _exportAsExcel() async {
    setState(() => isExporting = true);
    try {
      var excel = excel_lib.Excel.createExcel();
      excel_lib.Sheet sheetObject = excel['CashBook'];

      sheetObject.appendRow([
        excel_lib.TextCellValue('Date'),
        excel_lib.TextCellValue('Type'),
        excel_lib.TextCellValue('Category'),
        excel_lib.TextCellValue('Description'),
        excel_lib.TextCellValue('Amount'),
      ]);

      for (var trans in allTransactions) {
        sheetObject.appendRow([
          excel_lib.TextCellValue(DateFormat('dd/MM/yyyy').format(trans.date)),
          excel_lib.TextCellValue(trans.type.toUpperCase()),
          excel_lib.TextCellValue(trans.category),
          excel_lib.TextCellValue(
            trans.description.isEmpty ? '-' : trans.description,
          ),
          excel_lib.DoubleCellValue(trans.amount),
        ]);
      }

      sheetObject.appendRow([excel_lib.TextCellValue('')]);
      sheetObject.appendRow([
        excel_lib.TextCellValue('Total Income:'),
        excel_lib.TextCellValue(''),
        excel_lib.TextCellValue(''),
        excel_lib.TextCellValue(''),
        excel_lib.DoubleCellValue(summary['income'] ?? 0),
      ]);
      sheetObject.appendRow([
        excel_lib.TextCellValue('Total Expense:'),
        excel_lib.TextCellValue(''),
        excel_lib.TextCellValue(''),
        excel_lib.TextCellValue(''),
        excel_lib.DoubleCellValue(summary['expense'] ?? 0),
      ]);
      sheetObject.appendRow([
        excel_lib.TextCellValue('Net Balance:'),
        excel_lib.TextCellValue(''),
        excel_lib.TextCellValue(''),
        excel_lib.TextCellValue(''),
        excel_lib.DoubleCellValue(summary['balance'] ?? 0),
      ]);

      var fileBytes = excel.save();
      final directory = await getApplicationDocumentsDirectory();
      final fileName =
          'cashbook_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';
      final filePath = '${directory.path}/$fileName';

      File(filePath)
        ..createSync(recursive: true)
        ..writeAsBytesSync(fileBytes!);

      await Share.shareXFiles([
        XFile(filePath),
      ], text: 'Cash Book Excel Report');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Excel exported successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error exporting Excel: $e')));
      }
    } finally {
      setState(() => isExporting = false);
    }
  }

  Future<void> _exportAsCSV() async {
    setState(() => isExporting = true);
    try {
      String csv = 'Date,Type,Category,Description,Amount\n';

      for (var trans in allTransactions) {
        csv += '${DateFormat('dd/MM/yyyy').format(trans.date)},';
        csv += '${trans.type.toUpperCase()},';
        csv += '${trans.category},';
        csv += '${trans.description.isEmpty ? '-' : trans.description},';
        csv += '${trans.amount}\n';
      }

      csv += '\n';
      csv += 'Total Income,,,₹,${summary['income'] ?? 0}\n';
      csv += 'Total Expense,,,₹,${summary['expense'] ?? 0}\n';
      csv += 'Net Balance,,,₹,${summary['balance'] ?? 0}\n';

      final directory = await getApplicationDocumentsDirectory();
      final fileName =
          'cashbook_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.csv';
      final filePath = '${directory.path}/$fileName';

      File(filePath)
        ..createSync(recursive: true)
        ..writeAsStringSync(csv);

      await Share.shareXFiles([XFile(filePath)], text: 'Cash Book CSV Report');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('CSV exported successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error exporting CSV: $e')));
      }
    } finally {
      setState(() => isExporting = false);
    }
  }
}

// ============================================================================
// CATEGORY ANALYTICS SCREEN (CHANGED FROM PRODUCT ANALYTICS)
// ============================================================================

class CategoryAnalyticsScreen extends StatefulWidget {
  const CategoryAnalyticsScreen({Key? key}) : super(key: key);

  @override
  State<CategoryAnalyticsScreen> createState() =>
      _CategoryAnalyticsScreenState();
}

class _CategoryAnalyticsScreenState extends State<CategoryAnalyticsScreen> {
  final DatabaseService _dbService = DatabaseService();
  List<TransactionModel> allTransactions = [];
  List<String> categories = [];
  String? selectedCategory;
  String selectedPeriod = 'Month';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final trans = await _dbService.getTransactions();
    final cats = trans.map((t) => t.category).toSet().toList();

    setState(() {
      allTransactions = trans;
      categories = cats;
    });
  }

  List<TransactionModel> _getCategoryTransactions() {
    if (selectedCategory == null) return [];
    return allTransactions
        .where((t) => t.category == selectedCategory)
        .toList();
  }

  Map<String, List<TransactionModel>> _groupByPeriod() {
    final categoryTrans = _getCategoryTransactions();
    Map<String, List<TransactionModel>> grouped = {};

    for (var trans in categoryTrans) {
      String key;
      switch (selectedPeriod) {
        case 'Week':
          final weekStart = _getWeekStart(trans.date);
          final weekEnd = weekStart.add(const Duration(days: 6));
          key =
              '${DateFormat('dd MMM').format(weekStart)} - ${DateFormat('dd MMM yyyy').format(weekEnd)}';
          break;
        case 'Year':
          key = DateFormat('yyyy').format(trans.date);
          break;
        case 'Month':
        default:
          key = DateFormat('MMMM yyyy').format(trans.date);
          break;
      }

      if (!grouped.containsKey(key)) {
        grouped[key] = [];
      }
      grouped[key]!.add(trans);
    }

    return grouped;
  }

  DateTime _getWeekStart(DateTime date) {
    return date.subtract(Duration(days: date.weekday - 1));
  }

  double _calculateTotal(List<TransactionModel> transactions, String type) {
    return transactions
        .where((t) => t.type == type)
        .fold(0.0, (sum, t) => sum + t.amount);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.blue.withOpacity(0.1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Category Analytics',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedCategory,
                  decoration: const InputDecoration(
                    labelText: 'Select Category',
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                    prefixIcon: Icon(Icons.category),
                  ),
                  hint: const Text('Choose a category to analyze'),
                  items:
                      categories.map((category) {
                        return DropdownMenuItem(
                          value: category,
                          child: Text(category),
                        );
                      }).toList(),
                  onChanged: (value) {
                    setState(() {
                      selectedCategory = value;
                    });
                  },
                ),
                if (selectedCategory != null) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                              value: 'Week',
                              label: Text('Week'),
                              icon: Icon(Icons.calendar_view_week, size: 16),
                            ),
                            ButtonSegment(
                              value: 'Month',
                              label: Text('Month'),
                              icon: Icon(Icons.calendar_view_month, size: 16),
                            ),
                            ButtonSegment(
                              value: 'Year',
                              label: Text('Year'),
                              icon: Icon(Icons.calendar_today, size: 16),
                            ),
                          ],
                          selected: {selectedPeriod},
                          onSelectionChanged: (Set<String> newSelection) {
                            setState(() {
                              selectedPeriod = newSelection.first;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child:
                selectedCategory == null
                    ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.category_outlined,
                            size: 80,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            categories.isEmpty
                                ? 'No categories yet'
                                : 'Select a category to view analytics',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 16,
                            ),
                          ),
                          if (categories.isEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Add transactions to create categories',
                              style: TextStyle(
                                color: Colors.grey[500],
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ],
                      ),
                    )
                    : _buildAnalytics(),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalytics() {
    final categoryTrans = _getCategoryTransactions();
    final groupedData = _groupByPeriod();
    final sortedKeys =
        groupedData.keys.toList()..sort((a, b) => b.compareTo(a));

    final totalIncome = _calculateTotal(categoryTrans, 'income');
    final totalExpense = _calculateTotal(categoryTrans, 'expense');
    final netAmount = totalIncome - totalExpense;

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue[400]!, Colors.blue[600]!],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.blue.withOpacity(0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Text(
                selectedCategory!,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Total: ${categoryTrans.length} transactions',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _buildSummaryBox(
                      'Income',
                      totalIncome,
                      Icons.arrow_upward,
                      Colors.green[300]!,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildSummaryBox(
                      'Expense',
                      totalExpense,
                      Icons.arrow_downward,
                      Colors.red[300]!,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Net: ',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                    Text(
                      '₹${netAmount.toStringAsFixed(2)}',
                      style: TextStyle(
                        color:
                            netAmount >= 0
                                ? Colors.green[200]
                                : Colors.red[200],
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Icon(Icons.timeline, color: Colors.blue[700]),
              const SizedBox(width: 8),
              Text(
                '$selectedPeriod-wise Breakdown',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue[700],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: sortedKeys.length,
            itemBuilder: (context, index) {
              final periodKey = sortedKeys[index];
              final periodTrans = groupedData[periodKey]!;
              final income = _calculateTotal(periodTrans, 'income');
              final expense = _calculateTotal(periodTrans, 'expense');
              final balance = income - expense;

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                elevation: 2,
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.all(16),
                  childrenPadding: const EdgeInsets.all(16),
                  title: Text(
                    periodKey,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${periodTrans.length} transaction${periodTrans.length > 1 ? 's' : ''}',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '₹${balance.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: balance >= 0 ? Colors.green : Colors.red,
                        ),
                      ),
                      Text(
                        'Net',
                        style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildPeriodStat(
                              'Income',
                              income,
                              Icons.arrow_upward,
                              Colors.green,
                            ),
                          ),
                          Container(
                            width: 1,
                            height: 40,
                            color: Colors.grey[300],
                          ),
                          Expanded(
                            child: _buildPeriodStat(
                              'Expense',
                              expense,
                              Icons.arrow_downward,
                              Colors.red,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...periodTrans.map((trans) {
                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor:
                              trans.type == 'income'
                                  ? Colors.green.withOpacity(0.2)
                                  : Colors.red.withOpacity(0.2),
                          child: Icon(
                            trans.type == 'income' ? Icons.add : Icons.remove,
                            size: 16,
                            color:
                                trans.type == 'income'
                                    ? Colors.green
                                    : Colors.red,
                          ),
                        ),
                        title: Text(
                          trans.description.isEmpty
                              ? 'No description'
                              : trans.description,
                          style: const TextStyle(fontSize: 14),
                        ),
                        subtitle: Text(
                          DateFormat('dd MMM yyyy').format(trans.date),
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: Text(
                          '₹${trans.amount.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color:
                                trans.type == 'income'
                                    ? Colors.green
                                    : Colors.red,
                          ),
                        ),
                      );
                    }).toList(),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryBox(
    String label,
    double amount,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            '₹${amount.toStringAsFixed(2)}',
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodStat(
    String label,
    double amount,
    IconData icon,
    Color color,
  ) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 2),
        Text(
          '₹${amount.toStringAsFixed(2)}',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: color,
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}
