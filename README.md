# EA Infrastructure MQL5

## Modern Modular Trading Infrastructure for MetaTrader 5

A professional, extensible Expert Advisor infrastructure that provides a complete framework for developing trading strategies in MQL5. Built with modularity and flexibility in mind, allowing easy integration of custom trading methods.

## 🏗️ Architecture

### Core Features
- **Modular Design**: Plug-and-play trading methods system
- **Risk Management**: Built-in position sizing and risk control
- **State Management**: Persistent state tracking across sessions
- **Spread Control**: Advanced spread filtering and validation
- **Distance Control**: ATR-based dynamic distance calculations
- **Order Management**: Comprehensive order handling and tracking
- **Reversal System**: Smart stop-loss reversal logic
- **Panel Interface**: Visual trading panel for monitoring

### v7.1 Features
- **Method Interfaces**: Clean separation between main and auxiliary methods
- **Dynamic TP/SL**: ATR-based take profit and stop loss calculations
- **Multi-Method Support**: Framework supports multiple trading strategies
- **Isolated Architecture**: Completely separated v7 ecosystem

## 📁 Project Structure

```
EA-Infrastructure-MQL5/
├── Experts/
│   └── EA-HedgeLine_v7_1_Modular.mq5    # Main EA file
├── Include/
│   └── HedgeLine_v7/                     # v7.1 modules
│       ├── TrackingManager_v7.mqh        # Trade tracking and logging
│       ├── SpreadManager_v7.mqh          # Spread validation
│       ├── StateManager_v7.mqh           # System state management
│       ├── OrderManager_v7.mqh           # Order operations
│       ├── DistanceControl_v7.mqh        # Distance calculations
│       ├── PanelManager_v7.mqh           # Visual panel
│       ├── ReversalManager_v7.mqh        # Reversal logic
│       └── Methods/                       # Trading methods
│           ├── BaseMethod.mqh            # Method interfaces
│           ├── HedgeLineMethod.mqh       # HedgeLine strategy
│           └── SupDemMethod.mqh          # Support/Resistance
└── legacy/                                # Previous versions (v1-v6)
    ├── Experts/
    └── Include/
```

## 🚀 Quick Start

1. **Installation**
   - Copy the entire structure to your MT5 data folder
   - Maintain the exact directory structure

2. **Compilation**
   - Open `EA-HedgeLine_v7_1_Modular.mq5` in MetaEditor
   - Press F7 to compile
   - The EA will be available in MT5

3. **Configuration**
   - Main Method: Select trading strategy
   - Auxiliary Method: Optional filters
   - Risk Settings: Configure lot size and limits
   - Debug Mode: Enable for detailed logging

## 🔧 Extending the Framework

### Adding a New Trading Method

1. Create a new file in `/Include/HedgeLine_v7/Methods/`
2. Implement the `IMainMethod` interface:

```mql5
class CMyMethod : public IMainMethod {
    virtual bool Init(string symbol, ENUM_TIMEFRAMES period, bool debug);
    virtual TradingSignal GetSignal();
    virtual string GetMethodName();
    virtual void OnTick();
    virtual void OnTrade();
    virtual void SetDistanceManager(CDistanceControl* distMgr);
};
```

3. Add the method to the enum in the main EA
4. Add initialization case in `InitializeMethods()`

## 📊 Trading Methods

### HedgeLine Method (Built-in)
- Places bidirectional pending orders
- ATR-based distance calculation
- Automatic order management

### Support/Resistance Method (Auxiliary)
- Volume-based S/R detection
- Signal filtering based on key levels
- Adjustable strength parameters

## ⚙️ Configuration Parameters

### Main Settings
- `InpLotSize`: Trading volume
- `InpMagicNumber`: EA identifier
- `InpMaxDailyLoss`: Daily loss limit
- `InpMaxDailyProfit`: Daily profit target

### Dynamic TP/SL
- `InpUseDynamicTPSL`: Enable ATR-based TP/SL
- `InpDynamicTPMultiplier`: ATR multiplier for TP
- `InpDynamicSLMultiplier`: ATR multiplier for SL

### Risk Management
- `InpMaxReversals`: Maximum reversal trades
- `InpReversalLotMultiplier`: Lot size multiplier
- `InpMaxDailyTrades`: Daily trade limit

## 📈 Performance & Testing

The framework includes comprehensive error handling and validation:
- Input parameter validation
- Spread checking
- Distance validation
- State persistence
- Error logging

## 🛠️ Development

### Requirements
- MetaTrader 5 Build 3000+
- MQL5 compiler
- Windows OS (or Wine for Linux/Mac)

### Testing
- Use Strategy Tester for backtesting
- Enable debug mode for detailed logs
- Monitor the visual panel during testing

## 📝 Version History

- **v7.1**: Complete modular architecture with isolated v7 ecosystem
- **v6.0**: Legacy version with integrated methods
- **v5.0**: Added reversal management
- **v4.0**: Introduced state management
- **v3.0**: Added spread control
- **v2.0**: Basic order management
- **v1.0**: Initial implementation

## 📄 License

This project is proprietary software. All rights reserved.

## 🤝 Contributing

For bug reports or feature requests, please open an issue in the repository.

## 📧 Contact

For support or inquiries, please contact through the repository.

---

**Note**: This EA is for educational and trading purposes. Always test thoroughly in demo accounts before live trading.