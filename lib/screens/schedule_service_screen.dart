import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import '../services/auth_service.dart';
import 'payment_screen.dart';
import 'cars_screen.dart';

class ScheduleServiceScreen extends StatefulWidget {
  final String serviceTitle;
  final Color serviceColor;
  final IconData serviceIcon;
  final AuthService authService;

  const ScheduleServiceScreen({
    super.key,
    required this.serviceTitle,
    required this.serviceColor,
    required this.serviceIcon,
    required this.authService,
  });

  @override
  State<ScheduleServiceScreen> createState() => _ScheduleServiceScreenState();
}

class _ScheduleServiceScreenState extends State<ScheduleServiceScreen> {
  DateTime _selectedDate = DateTime.now();
  String? _selectedTime;
  bool _isLoading = false;
  Map<String, String> _bookedTimeSlots = {};
  Map<String, dynamic>? _selectedCar;
  List<Map<String, dynamic>> _userCars = [];

  final List<String> _timeSlots = [];
  late DateFormat _dateFormat;
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // Mapa de preços dos serviços
  static const Map<String, double> _servicePrices = {
    'Lavagem': 50.0,
    'Espelhamento': 120.0,
    'Polimento': 150.0,
    'Higienização': 100.0,
    'Hidratação de Couro': 180.0,
    'Leva e Traz': 30.0,
  };

  @override
  void initState() {
    super.initState();
    _initializeDateFormatting();
    _generateTimeSlots();
    _loadBookedTimeSlots();
    _loadUserCars();
  }

  Future<void> _initializeDateFormatting() async {
    await initializeDateFormatting('pt_BR', null);
    _dateFormat = DateFormat('dd/MM/yyyy', 'pt_BR');
  }

  void _generateTimeSlots() {
    _timeSlots.clear();
    final startTime = DateTime(2024, 1, 1, 8, 0);
    final endTime = DateTime(2024, 1, 1, 17, 0);

    DateTime currentSlot = startTime;
    while (currentSlot.isBefore(endTime) || currentSlot.hour == endTime.hour) {
      _timeSlots.add(DateFormat('HH:mm').format(currentSlot));
      currentSlot = currentSlot.add(const Duration(minutes: 30));
    }
  }

  Future<void> _loadBookedTimeSlots() async {
    setState(() => _isLoading = true);
    try {
      final startOfDay = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
      );
      final endOfDay = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        23,
        59,
        59,
      );

      debugPrint(
          'Checando compromissos entre ${startOfDay.toString()} e ${endOfDay.toString()}');

      final querySnapshot = await FirebaseFirestore.instance
          .collection('appointments')
          .where('dateTime', isGreaterThanOrEqualTo: startOfDay)
          .where('dateTime', isLessThan: endOfDay)
          .get();

      debugPrint('Encontrado ${querySnapshot.docs.length} compromissos');

      final Map<String, String> bookedSlots = {};
      for (var doc in querySnapshot.docs) {
        final data = doc.data();
        if (data['status'] == 'scheduled') {
          final dateTime = (data['dateTime'] as Timestamp).toDate();
          final service = data['service'] as String;
          final timeSlot = DateFormat('HH:mm').format(dateTime);
          bookedSlots[timeSlot] = service;
          debugPrint('Booked slot: $timeSlot for service: $service');
        }
      }

      setState(() {
        _bookedTimeSlots = bookedSlots;
      });
    } catch (e) {
      debugPrint('Erro ao carregar horários : $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao carregar horários: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadUserCars() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        final snapshot = await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('cars')
            .orderBy('createdAt', descending: true)
            .get();

        setState(() {
          _userCars = snapshot.docs
              .map((doc) => {...doc.data(), 'id': doc.id})
              .toList();
        });
      }
    } catch (e) {
      debugPrint('Error loading cars: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao carregar carros: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Função para obter o valor do serviço
  double _getServicePrice() {
    return _servicePrices[widget.serviceTitle] ?? 100.0;
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 30)),
      locale: const Locale('pt', 'BR'),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: widget.serviceColor,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
        _selectedTime = null;
      });
      _loadBookedTimeSlots();
    }
  }

  Future<void> _scheduleService() async {
    if (_selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor, selecione um horário'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_selectedCar == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor, selecione um carro'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Usuário não autenticado');

      final timeParts = _selectedTime!.split(':');
      final dateTime = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        int.parse(timeParts[0]),
        int.parse(timeParts[1]),
      );

      debugPrint('Checking if time slot is available: ${dateTime.toString()}');

      final querySnapshot = await FirebaseFirestore.instance
          .collection('appointments')
          .where('dateTime', isEqualTo: dateTime)
          .where('status', isEqualTo: 'scheduled')
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        if (mounted) {
          final existingService =
              querySnapshot.docs.first.data()['service'] as String;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Este horário já está reservado para $existingService. Por favor, escolha outro horário.',
              ),
              backgroundColor: Colors.orange,
            ),
          );

          await _loadBookedTimeSlots();
          setState(() => _isLoading = false);
        }
        return;
      }

      if (mounted) {
        final bool? shouldContinue = await showDialog<bool>(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text(
                'Confirmar Agendamento',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Serviço: ${widget.serviceTitle}',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Data: ${_dateFormat.format(_selectedDate)}',
                    style: GoogleFonts.poppins(),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Horário: $_selectedTime',
                    style: GoogleFonts.poppins(),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Carro: ${_selectedCar!['name']} ${_selectedCar!['model']}',
                    style: GoogleFonts.poppins(),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Placa: ${_selectedCar!['plate']}',
                    style: GoogleFonts.poppins(),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(
                    'Cancelar',
                    style: GoogleFonts.poppins(
                      color: Colors.grey[600],
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(
                    'Confirmar',
                    style: GoogleFonts.poppins(
                      color: widget.serviceColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        );

        if (shouldContinue == true) {
          // Obter o valor do serviço do mapa de preços
          final serviceAmount = _servicePrices[widget.serviceTitle] ?? 100.0;

          debugPrint('Serviço: ${widget.serviceTitle}');
          debugPrint('Valor: R\$ ${serviceAmount.toStringAsFixed(2)}');

          // Navegar para a tela de pagamento
          if (mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => PaymentScreen(
                  amount: serviceAmount, // Valor dinâmico do serviço
                  serviceTitle: widget.serviceTitle,
                  serviceDescription: 'Agendamento de ${widget.serviceTitle}',
                  carId: _selectedCar!['id'],
                  carModel: _selectedCar!['model'],
                  carPlate: _selectedCar!['plate'],
                ),
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Error scheduling service: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao agendar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Agendar ${widget.serviceTitle}',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadBookedTimeSlots,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: widget.serviceColor,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                widget.serviceIcon,
                                color: Colors.white,
                                size: 32,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.serviceTitle,
                                    style: GoogleFonts.poppins(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    'Selecione a data e horário desejados',
                                    style: GoogleFonts.poppins(
                                      color: Colors.black54,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Valor: R\$ ${_getServicePrice().toStringAsFixed(2)}',
                                    style: GoogleFonts.poppins(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: widget.serviceColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Selecione o Carro',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_userCars.isEmpty)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              Icon(
                                Icons.directions_car_outlined,
                                size: 48,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Nenhum carro cadastrado',
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  color: Colors.grey[600],
                                ),
                              ),
                              const SizedBox(height: 8),
                              ElevatedButton(
                                onPressed: () async {
                                  final result = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => const CarsScreen(),
                                    ),
                                  );
                                  if (result == true) {
                                    _loadUserCars();
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: widget.serviceColor,
                                  foregroundColor: Colors.white,
                                ),
                                child: Text(
                                  'Adicionar Carro',
                                  style: GoogleFonts.poppins(),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      Column(
                        children: [
                          ..._userCars.map((car) {
                            final isSelected = car['id'] == _selectedCar?['id'];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: InkWell(
                                onTap: () {
                                  setState(() {
                                    _selectedCar = car;
                                  });
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: Checkbox(
                                          value: isSelected,
                                          onChanged: (bool? value) {
                                            setState(() {
                                              _selectedCar =
                                                  value! ? car : null;
                                            });
                                          },
                                          activeColor: widget.serviceColor,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              car['name'],
                                              style: GoogleFonts.poppins(
                                                fontWeight: FontWeight.w500,
                                                fontSize: 16,
                                              ),
                                            ),
                                            Text(
                                              '${car['model']} - ${car['plate']}',
                                              style: GoogleFonts.poppins(
                                                color: Colors.grey[600],
                                                fontSize: 14,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: () async {
                              final result = await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const CarsScreen(),
                                ),
                              );
                              if (result == true) {
                                _loadUserCars();
                              }
                            },
                            icon: Icon(
                              Icons.add,
                              color: widget.serviceColor,
                            ),
                            label: Text(
                              'Adicionar outro carro',
                              style: GoogleFonts.poppins(
                                color: widget.serviceColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 24),
                    Text(
                      'Data',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () => _selectDate(context),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _dateFormat.format(_selectedDate),
                              style: GoogleFonts.poppins(fontSize: 16),
                            ),
                            Icon(
                              Icons.calendar_today,
                              color: widget.serviceColor,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Horário',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        childAspectRatio: 2,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: _timeSlots.length,
                      itemBuilder: (context, index) {
                        final timeSlot = _timeSlots[index];
                        final isSelected = timeSlot == _selectedTime;
                        final isBooked = _bookedTimeSlots.containsKey(timeSlot);
                        final bookedService = _bookedTimeSlots[timeSlot];

                        return Tooltip(
                          message: isBooked
                              ? 'Reservado: $bookedService'
                              : 'Disponível',
                          child: InkWell(
                            onTap: isBooked
                                ? null
                                : () {
                                    setState(() {
                                      _selectedTime = timeSlot;
                                    });
                                  },
                            child: Container(
                              decoration: BoxDecoration(
                                color: isBooked
                                    ? Colors.grey.shade300
                                    : isSelected
                                        ? widget.serviceColor
                                        : Colors.white,
                                border: Border.all(
                                  color: isBooked
                                      ? Colors.grey.shade400
                                      : isSelected
                                          ? widget.serviceColor
                                          : Colors.grey.shade300,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(
                                child: Text(
                                  timeSlot,
                                  style: GoogleFonts.poppins(
                                    color: isBooked
                                        ? Colors.grey.shade600
                                        : isSelected
                                            ? Colors.white
                                            : Colors.black87,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    decoration: isBooked
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    if (_bookedTimeSlots.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade300,
                              border: Border.all(color: Colors.grey.shade400),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Horários indisponíveis',
                            style: GoogleFonts.poppins(
                              color: Colors.grey.shade600,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: const Color.fromRGBO(0, 0, 0, 0).withValues(),
              blurRadius: 10,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: _isLoading ? null : _scheduleService,
          style: ElevatedButton.styleFrom(
            backgroundColor: widget.serviceColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: _isLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : Text(
                  'Confirmar Agendamento',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
      ),
    );
  }
}
