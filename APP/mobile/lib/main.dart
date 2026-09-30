
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_client/web_socket_client.dart';

const apiBase = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:8000',
);
const wsBase = String.fromEnvironment(
  'WS_BASE_URL',
  defaultValue: 'ws://10.0.2.2:8000',
);

void main() => runApp(const RadarApp());

class RadarApp extends StatelessWidget {
  const RadarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Futures AI Radar',
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const RadarHome(),
    );
  }
}

class RadarHome extends StatefulWidget {
  const RadarHome({super.key});
  @override State<RadarHome> createState() => _RadarHomeState();
}

class _RadarHomeState extends State<RadarHome> {
  List<dynamic> items = [];
  bool loading = true;
  String error = '';

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() { loading = true; error = ''; });
    try {
      final r = await http.get(Uri.parse('$apiBase/scanner'));
      if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
      final data = jsonDecode(r.body);
      setState(() => items = data['items'] ?? []);
    } catch (e) {
      setState(() => error = 'Не удалось получить данные: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Futures AI Radar'),
        actions: [IconButton(onPressed: load, icon: const Icon(Icons.refresh))],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error.isNotEmpty
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(error, textAlign: TextAlign.center),
                ))
              : RefreshIndicator(
                  onRefresh: load,
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      _banner(),
                      const SizedBox(height: 12),
                      ...items.map((x) => _card(x)),
                    ],
                  ),
                ),
    );
  }

  Widget _banner() => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome),
          const SizedBox(width: 12),
          Expanded(child: Text(
            'Сканер ищет необычную волатильность. Откройте инструмент для real-time графика.',
            style: Theme.of(context).textTheme.bodyMedium,
          )),
        ],
      ),
    ),
  );

  Widget _card(dynamic x) {
    final signal = x['signal'] ?? 'WAIT';
    final isSetup = signal != 'WAIT';
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => SetupPage(symbol: x['symbol']),
        )),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Text(x['symbol'], style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  _chip(signal, isSetup),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _metric('Цена', '${x['price']}'),
                  _metric('Vol score', '${x['volatility_score']}'),
                  _metric('ATR', '${x['atr_pct']}%'),
                  _metric('Volume', '${x['volume_ratio']}x'),
                ],
              ),
              const SizedBox(height: 10),
              LinearProgressIndicator(value: (x['volatility_score'] / 100).clamp(0, 1)),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Тренд: ${x['trend']} • 24h: ${x['change_24h'].toStringAsFixed(2)}%'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String text, bool active) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      color: active ? Colors.indigo.withOpacity(.35) : Colors.grey.withOpacity(.2),
    ),
    child: Text(text),
  );

  Widget _metric(String a, String b) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(a, style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
      const SizedBox(height: 3),
      Text(b, style: const TextStyle(fontWeight: FontWeight.w600)),
    ],
  );
}

class SetupPage extends StatefulWidget {
  final String symbol;
  const SetupPage({super.key, required this.symbol});
  @override State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  Map<String, dynamic>? data;
  bool loading = true;
  String error = '';
  int tab = 0;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = await http.get(Uri.parse('$apiBase/setup?symbol=${widget.symbol}'));
      if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
      setState(() => data = jsonDecode(r.body));
    } catch (e) {
      setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.symbol),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(child: Text(
              'LIVE',
              style: TextStyle(color: Colors.greenAccent.shade400, fontWeight: FontWeight.bold),
            )),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error.isNotEmpty
              ? Center(child: Text(error))
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: SegmentedButton<int>(
                        segments: const [
                          ButtonSegment(value: 0, label: Text('График'), icon: Icon(Icons.candlestick_chart)),
                          ButtonSegment(value: 1, label: Text('Сигнал'), icon: Icon(Icons.analytics_outlined)),
                        ],
                        selected: {tab},
                        onSelectionChanged: (s) => setState(() => tab = s.first),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: tab == 0
                          ? FuturesChartPage(symbol: widget.symbol)
                          : _signalBody(),
                    ),
                  ],
                ),
    );
  }

  Widget _signalBody() {
    final d = data!;
    final signal = d['signal'];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(children: [
            const Icon(Icons.bolt, size: 32),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Модельный сценарий', style: TextStyle(color: Colors.grey)),
              Text(signal, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
            ]),
          ]),
        )),
        const SizedBox(height: 14),
        Card(child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            _row('Текущая цена', '${d['price']}'),
            _row('Зона входа', '${d['entry_low']} — ${d['entry_high']}'),
            _row('Stop / invalidation', '${d['stop']}'),
            _row('TP1', '${d['tp1']}'),
            _row('TP2', '${d['tp2']}'),
            _row('Confidence', '${d['confidence']}%'),
          ]),
        )),
        const SizedBox(height: 14),
        Text('Факторы', style: Theme.of(context).textTheme.titleLarge),
        ...(d['reasons'] as List).map((e) => ListTile(
          dense: true,
          leading: const Icon(Icons.analytics_outlined),
          title: Text('$e'),
        )),
        const SizedBox(height: 8),
        Text('AI-анализ', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Card(child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(d['ai_comment'] ?? ''),
        )),
        const SizedBox(height: 18),
        const Text(
          'Entry/Stop/TP — расчётные уровни исследовательской модели. '
          'Они не являются гарантией результата или персональной инвестиционной рекомендацией.',
          style: TextStyle(color: Colors.orangeAccent),
        ),
      ],
    );
  }

  Widget _row(String a, String b) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(children: [
      Expanded(child: Text(a, style: TextStyle(color: Colors.grey.shade400))),
      Flexible(child: Text(b, textAlign: TextAlign.right)),
    ]),
  );
}

class CandlePoint {
  CandlePoint({
    required this.time,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
    this.closed = true,
    this.ema20,
    this.ema50,
    this.atrPct,
    this.rsi,
  });

  int time;
  double open;
  double high;
  double low;
  double close;
  double volume;
  bool closed;
  double? ema20;
  double? ema50;
  double? atrPct;
  double? rsi;

  factory CandlePoint.fromJson(Map<String, dynamic> j) => CandlePoint(
    time: (j['time'] as num).toInt(),
    open: (j['open'] as num).toDouble(),
    high: (j['high'] as num).toDouble(),
    low: (j['low'] as num).toDouble(),
    close: (j['close'] as num).toDouble(),
    volume: (j['volume'] as num).toDouble(),
    closed: j['closed'] != false,
    ema20: (j['ema20'] as num?)?.toDouble(),
    ema50: (j['ema50'] as num?)?.toDouble(),
    atrPct: (j['atrPct'] as num?)?.toDouble(),
    rsi: (j['rsi'] as num?)?.toDouble(),
  );

  Map<String, dynamic> toJson() => {
    'time': time, 'open': open, 'high': high, 'low': low,
    'close': close, 'volume': volume, 'closed': closed,
    if (ema20 != null) 'ema20': ema20,
    if (ema50 != null) 'ema50': ema50,
    if (atrPct != null) 'atrPct': atrPct,
    if (rsi != null) 'rsi': rsi,
  };
}

class FuturesChartPage extends StatefulWidget {
  final String symbol;
  const FuturesChartPage({super.key, required this.symbol});
  @override State<FuturesChartPage> createState() => _FuturesChartPageState();
}

class _FuturesChartPageState extends State<FuturesChartPage> {
  final List<CandlePoint> candles = [];
  WebSocket? socket;
  StreamSubscription? messageSub;
  StreamSubscription? connectionSub;
  String interval = '5m';
  bool connected = false;
  bool loading = true;
  String error = '';
  int visible = 100;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    messageSub?.cancel();
    connectionSub?.cancel();
    socket?.close();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    setState(() { loading = true; error = ''; });
    try {
      final uri = Uri.parse('$apiBase/chart?symbol=${widget.symbol}&interval=$interval&limit=240');
      final r = await http.get(uri);
      if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      final rows = (body['candles'] as List)
          .map((e) => CandlePoint.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      setState(() {
        candles
          ..clear()
          ..addAll(rows);
        visible = math.min(120, candles.length).toInt();
      });
      _connect();
    } catch (e) {
      setState(() => error = 'График недоступен: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _connect() {
    messageSub?.cancel();
    connectionSub?.cancel();
    socket?.close();

    final url = '$wsBase/ws/market/${widget.symbol.toLowerCase()}?interval=$interval';
    final ws = WebSocket(
      Uri.parse(url),
      timeout: const Duration(seconds: 10),
      backoff: const BinaryExponentialBackoff(
        initial: Duration(seconds: 1),
        maximumStep: 5,
      ),
    );
    socket = ws;

    connectionSub = ws.connection.listen((state) {
      if (!mounted) return;
      setState(() {
        connected = state is Connected || state is Reconnected;
      });
    });

    messageSub = ws.messages.listen((message) {
      try {
        final m = jsonDecode(message as String) as Map<String, dynamic>;
        if (m['type'] != 'kline') return;
        final incoming = CandlePoint.fromJson(m);
        _upsertRealtime(incoming);
      } catch (_) {}
    });
  }

  void _upsertRealtime(CandlePoint incoming) {
    final idx = candles.indexWhere((c) => c.time == incoming.time);
    if (idx >= 0) {
      final old = candles[idx];
      incoming
        ..ema20 = old.ema20
        ..ema50 = old.ema50
        ..rsi = old.rsi
        ..atrPct = old.atrPct;
      candles[idx] = incoming;
    } else {
      candles.add(incoming);
      if (candles.length > 300) candles.removeAt(0);
    }
    _recalculateIndicators();

    if (mounted) setState(() {});
  }

  void _recalculateIndicators() {
    if (candles.isEmpty) return;
    const alpha20 = 2 / (20 + 1);
    const alpha50 = 2 / (50 + 1);
    double ema20 = candles.first.close;
    double ema50 = candles.first.close;
    final trs = <double>[];
    double prevClose = candles.first.close;
    final gains = <double>[];
    final losses = <double>[];

    for (int i = 0; i < candles.length; i++) {
      final c = candles[i];
      ema20 = c.close * alpha20 + ema20 * (1 - alpha20);
      ema50 = c.close * alpha50 + ema50 * (1 - alpha50);

      final tr = math.max(
        c.high - c.low,
        math.max((c.high - prevClose).abs(), (c.low - prevClose).abs()),
      );
      trs.add(tr);

      final delta = c.close - prevClose;
      gains.add(math.max(delta, 0));
      losses.add(math.max(-delta, 0));
      prevClose = c.close;

      c.ema20 = ema20;
      c.ema50 = ema50;
    }

    for (int i = 0; i < candles.length; i++) {
      final start = math.max(0, i - 13);
      final trSlice = trs.sublist(start, i + 1);
      final atr = trSlice.reduce((a, b) => a + b) / trSlice.length;
      candles[i].atrPct = candles[i].close == 0 ? 0 : atr / candles[i].close * 100;

      final rStart = math.max(0, i - 13);
      final g = gains.sublist(rStart, i + 1);
      final l = losses.sublist(rStart, i + 1);
      final avgGain = g.reduce((a, b) => a + b) / g.length;
      final avgLoss = l.reduce((a, b) => a + b) / l.length;
      if (avgLoss == 0) {
        candles[i].rsi = avgGain == 0 ? 50 : 100;
      } else {
        final rs = avgGain / avgLoss;
        candles[i].rsi = 100 - 100 / (1 + rs);
      }
    }
  }

  List<CandlePoint> get visibleCandles {
    final start = math.max(0, candles.length - visible).toInt();
    return candles.sublist(start);
  }

  String _price(double value) {
    if (value >= 1000) return value.toStringAsFixed(2);
    if (value >= 1) return value.toStringAsFixed(4);
    return value.toStringAsFixed(6);
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error.isNotEmpty) return Center(child: Text(error));

    final view = visibleCandles;
    if (view.isEmpty) return const Center(child: Text('Нет свечей'));

    final last = view.last;
    final trend = (last.ema20 ?? last.close) >= (last.ema50 ?? last.close) ? 'UP' : 'DOWN';

    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 18),
      children: [
        _toolbar(),
        const SizedBox(height: 8),
        _marketHeader(last, trend),
        const SizedBox(height: 8),
        _chartCard(view),
        const SizedBox(height: 8),
        _indicatorCard('EMA 20 / EMA 50', _emaChart(view), 'trend'),
        const SizedBox(height: 8),
        _indicatorCard('RSI (14)', _rsiChart(view), '50 = neutral'),
        const SizedBox(height: 8),
        _indicatorCard('Volume', _volumeChart(view), 'real-time'),
        const SizedBox(height: 8),
        _indicatorCard('ATR %', _atrChart(view), '14 periods'),
      ],
    );
  }

  Widget _toolbar() => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (final t in const ['1m','5m','15m','1h','4h'])
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text(t),
              selected: interval == t,
              onSelected: (_) async {
                if (interval == t) return;
                setState(() => interval = t);
                await _loadHistory();
              },
            ),
          ),
      ],
    ),
  );

  Widget _marketHeader(CandlePoint c, String trend) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 9, height: 9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: connected ? Colors.greenAccent : Colors.orangeAccent,
            ),
          ),
          const SizedBox(width: 8),
          Text(connected ? 'LIVE' : 'RECONNECTING',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
          const SizedBox(width: 16),
          Text(_price(c.close),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
          const SizedBox(width: 8),
          Text('EMA20 ${_price(c.ema20 ?? c.close)}',
              style: const TextStyle(fontSize: 11)),
          const Spacer(),
          Text(trend, style: TextStyle(
            color: trend == 'UP' ? Colors.greenAccent : Colors.redAccent,
            fontWeight: FontWeight.bold,
          )),
        ],
      ),
    ),
  );

  Widget _chartCard(List<CandlePoint> view) {
    final spots = [
      for (int i = 0; i < view.length; i++)
        CandlestickSpot(
          x: i.toDouble(),
          open: view[i].open,
          high: view[i].high,
          low: view[i].low,
          close: view[i].close,
        ),
    ];

    final minY = view.map((e) => e.low).reduce(math.min);
    final maxY = view.map((e) => e.high).reduce(math.max);
    final pad = (maxY - minY) * .06;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 10, 8),
        child: SizedBox(
          height: 390,
          child: CandlestickChart(
            CandlestickChartData(
              minX: 0,
              maxX: math.max(1, spots.length - 1).toDouble(),
              minY: minY - pad,
              maxY: maxY + pad,
              candlestickSpots: spots,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: (maxY - minY) / 5,
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 62,
                    getTitlesWidget: (v, meta) => Text(
                      _price(v),
                      style: const TextStyle(fontSize: 9, color: Colors.white54),
                    ),
                  ),
                ),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: math.max(1.0, view.length / 5.0),
                    getTitlesWidget: (v, meta) {
                      final i = v.round().clamp(0, view.length - 1);
                      final dt = DateTime.fromMillisecondsSinceEpoch(view[i].time);
                      return Text(
                        '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}',
                        style: const TextStyle(fontSize: 9, color: Colors.white54),
                      );
                    },
                  ),
                ),
              ),
              candlestickTouchData: CandlestickTouchData(
                enabled: true,
                handleBuiltInTouches: true,
              ),
            ),
            duration: const Duration(milliseconds: 80),
          ),
        ),
      ),
    );
  }

  Widget _indicatorCard(String title, Widget chart, String subtitle) => Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 11)),
          ]),
          const SizedBox(height: 4),
          SizedBox(height: 110, child: chart),
        ],
      ),
    ),
  );

  Widget _emaChart(List<CandlePoint> view) {
    final e20 = [
      for (int i = 0; i < view.length; i++)
        FlSpot(i.toDouble(), view[i].ema20 ?? view[i].close),
    ];
    final e50 = [
      for (int i = 0; i < view.length; i++)
        FlSpot(i.toDouble(), view[i].ema50 ?? view[i].close),
    ];
    final values = [...e20, ...e50].map((e) => e.y).toList();
    final min = values.reduce(math.min);
    final max = values.reduce(math.max);
    final pad = (max - min).abs() * .08;
    return LineChart(
      LineChartData(
        minX: 0,
        maxX: math.max(1, view.length - 1).toDouble(),
        minY: min - pad,
        maxY: max + pad,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: const FlTitlesData(show: false),
        lineTouchData: const LineTouchData(enabled: true),
        lineBarsData: [
          LineChartBarData(
            spots: e20,
            isCurved: false,
            dotData: const FlDotData(show: false),
            barWidth: 1.5,
          ),
          LineChartBarData(
            spots: e50,
            isCurved: false,
            dotData: const FlDotData(show: false),
            barWidth: 1.5,
          ),
        ],
      ),
    );
  }

  Widget _rsiChart(List<CandlePoint> view) {
    final spots = [
      for (int i = 0; i < view.length; i++)
        FlSpot(i.toDouble(), view[i].rsi ?? 50),
    ];
    return LineChart(_lineData(spots, minY: 0, maxY: 100, lines: [30, 50, 70]));
  }

  Widget _atrChart(List<CandlePoint> view) {
    final spots = [
      for (int i = 0; i < view.length; i++)
        FlSpot(i.toDouble(), view[i].atrPct ?? 0),
    ];
    final max = spots.map((e) => e.y).fold<double>(0, math.max);
    return LineChart(_lineData(spots, minY: 0, maxY: math.max(1, max * 1.15), lines: []));
  }

  Widget _volumeChart(List<CandlePoint> view) {
    final max = view.map((e) => e.volume).fold<double>(0, math.max);
    return BarChart(
      BarChartData(
        minY: 0,
        maxY: max == 0 ? 1 : max * 1.1,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: const FlTitlesData(show: false),
        barGroups: [
          for (int i = 0; i < view.length; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: view[i].volume,
                width: math.max(1.0, 220 / view.length),
              ),
            ]),
        ],
      ),
    );
  }

  LineChartData _lineData(
    List<FlSpot> spots, {
    required double minY,
    required double maxY,
    required List<double> lines,
  }) => LineChartData(
    minX: 0,
    maxX: math.max(1, spots.length - 1).toDouble(),
    minY: minY,
    maxY: maxY,
    gridData: FlGridData(
      show: true,
      drawVerticalLine: false,
      horizontalInterval: (maxY - minY) / 2,
    ),
    borderData: FlBorderData(show: false),
    titlesData: const FlTitlesData(show: false),
    lineTouchData: LineTouchData(enabled: true),
    extraLinesData: ExtraLinesData(
      horizontalLines: [
        for (final y in lines)
          HorizontalLine(y: y, strokeWidth: 1, dashArray: [4, 4]),
      ],
    ),
    lineBarsData: [
      LineChartBarData(
        spots: spots,
        isCurved: false,
        dotData: const FlDotData(show: false),
        barWidth: 1.5,
      ),
    ],
  );
}
