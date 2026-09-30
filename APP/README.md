# Futures AI Radar

Мобильное приложение для мониторинга фьючерсного рынка:
- сканирует USDT-M фьючерсы Binance;
- ищет повышенную реализованную волатильность;
- считает ATR, RSI, EMA, объёмный импульс;
- формирует LONG/SHORT/WAIT setup;
- показывает гипотетические Entry / Stop / TP1 / TP2;
- имеет optional LLM-анализ через OpenAI Responses API;
- НЕ отправляет реальные ордера и не подключается к торговому аккаунту.

## Архитектура

- `backend/` — FastAPI + httpx + pandas/numpy
- `mobile/` — Flutter
- Backend получает публичные market-data Binance Futures REST API.
- Мобильное приложение обращается только к вашему backend.

## Быстрый запуск backend

```bash
cd backend
python -m venv .venv
# Linux/macOS:
source .venv/bin/activate
# Windows:
# .venv\Scripts\activate

pip install -r requirements.txt
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

Проверка:
`http://127.0.0.1:8000/health`

## Optional AI

Создайте `backend/.env`:

```env
OPENAI_API_KEY=your_key
OPENAI_MODEL=gpt-5.6-luna
```

Без ключа приложение всё равно работает: используется локальный аналитический движок.

## Запуск Flutter

Установите Flutter 3.x и Android Studio/Xcode.

```bash
cd mobile
flutter pub get
flutter run
```

Для Android-эмулятора backend на компьютере доступен по:
`http://10.0.2.2:8000`

Для физического телефона укажите LAN IP компьютера:

```bash
flutter run --dart-define=API_BASE_URL=http://192.168.1.100:8000
```

## Важно

Это исследовательский/образовательный инструмент. Сигналы являются модельными сценариями, а не персональной инвестиционной рекомендацией. Не используйте расчётные уровни как гарантию результата. Перед реальной торговлей добавьте аутентификацию, rate limiting, хранение секретов, аудит и отдельный режим paper trading.


## Real-time professional chart

Версия 1.1 добавляет:
- OHLCV history через `/chart`;
- Binance USDⓈ-M Futures kline WebSocket через backend `/ws/market/{symbol}`;
- автоматический reconnect;
- real-time обновление текущей свечи без polling;
- таймфреймы 1m / 5m / 15m / 1h / 4h;
- интерактивный candlestick chart;
- EMA20 / EMA50;
- RSI(14);
- ATR%;
- volume;
- live/reconnecting status;
- touch tooltip и масштабирование/трансформации `fl_chart`.

Binance market streams используют WebSocket endpoint для USDⓈ-M Futures; сервер Binance периодически разрывает соединение, поэтому клиентский слой должен поддерживать reconnect. citeturn0search6

Для Flutter используется `fl_chart` 1.2.0, который содержит `CandlestickChart` и `CandlestickSpot`. citeturn1search3turn1search1

### LAN / физический телефон

```bash
flutter run \
  --dart-define=API_BASE_URL=http://192.168.1.100:8000 \
  --dart-define=WS_BASE_URL=ws://192.168.1.100:8000
```

Для production используйте HTTPS/WSS:
```text
API_BASE_URL=https://api.example.com
WS_BASE_URL=wss://api.example.com
```


## AI signal mode
The `/setup` endpoint now uses the OpenAI Responses API as a decision layer when `OPENAI_API_KEY` is configured. The AI selects `LONG`, `SHORT`, or `WAIT` from the supplied market features; Entry/Stop/TP levels remain calculated server-side from ATR. Without an API key the app falls back to the deterministic technical model.

The signal is decision support, not a guarantee of profit or personalized financial advice.
