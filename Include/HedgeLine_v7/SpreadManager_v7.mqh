//+------------------------------------------------------------------+
//|                                              SpreadManager.mqh   |
//|                                  Gestão de Spread para HedgeLine |
//|                                  Copyright 2025, HedgeLine EA    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, HedgeLine EA"
#property link      "https://www.hedgeline.com"
#property version   "1.00"

//+------------------------------------------------------------------+
//| Classe para Gestão de Spread                                    |
//+------------------------------------------------------------------+
class CSpreadManager {
private:
    bool m_useFilter;           // Usar filtro de spread
    int m_maxSpread;           // Spread máximo configurado
    bool m_debugMode;          // Modo debug
    datetime m_lastDebugTime;  // Último tempo de debug
    datetime m_lastLogTime;    // Último tempo de log

public:
    //+------------------------------------------------------------------+
    //| Construtor                                                      |
    //+------------------------------------------------------------------+
    CSpreadManager() {
        m_useFilter = true;
        m_maxSpread = 100;
        m_debugMode = false;
        m_lastDebugTime = 0;
        m_lastLogTime = 0;
    }

    //+------------------------------------------------------------------+
    //| Inicializar                                                     |
    //+------------------------------------------------------------------+
    void Init(bool useFilter, int maxSpread, bool debugMode) {
        m_useFilter = useFilter;
        m_maxSpread = maxSpread;
        m_debugMode = debugMode;
    }

    //+------------------------------------------------------------------+
    //| Obter Spread Real Corrigido                                     |
    //+------------------------------------------------------------------+
    double GetRealSpread() {
        // Obter spread RAW do broker
        long spreadRaw = SymbolInfoInteger(Symbol(), SYMBOL_SPREAD);
        double spread = (double)spreadRaw;

        // CORREÇÃO DEFINITIVA: Sempre dividir por 10 para forex
        // Os dados mostram que o broker retorna em décimos de ponto
        string symbol = Symbol();
        bool isForex = (StringFind(symbol, "EUR") >= 0 ||
                       StringFind(symbol, "USD") >= 0 ||
                       StringFind(symbol, "GBP") >= 0 ||
                       StringFind(symbol, "JPY") >= 0 ||
                       StringFind(symbol, "CHF") >= 0 ||
                       StringFind(symbol, "CAD") >= 0 ||
                       StringFind(symbol, "AUD") >= 0 ||
                       StringFind(symbol, "NZD") >= 0);

        if(isForex) {
            // SEMPRE dividir por 10 para forex
            // 38 → 3.8 pontos, 56 → 5.6 pontos
            spread = spread / 10.0;

            // Debug apenas ocasionalmente
            if(m_debugMode) {
                datetime currentTime = TimeCurrent();
                if(currentTime - m_lastDebugTime > 300) {  // A cada 5 minutos
                    Print("Spread convertido: ", spreadRaw, " décimos → ",
                          DoubleToString(spread, 1), " pontos (",
                          DoubleToString(spread/10.0, 2), " pips)");
                    m_lastDebugTime = currentTime;
                }
            }
        }

        // Validação de sanidade
        if(spread <= 0) {
            MqlTick tick;
            if(SymbolInfoTick(Symbol(), tick)) {
                double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
                spread = (tick.ask - tick.bid) / point;

                // Se calculado manualmente para forex, também dividir por 10
                if(isForex && spread > 20) {
                    spread = spread / 10.0;
                }
            } else {
                spread = 5;  // Valor padrão seguro
            }
        }

        return spread;
    }

    //+------------------------------------------------------------------+
    //| Validar Condições de Spread                                     |
    //+------------------------------------------------------------------+
    bool ValidateSpread() {
        if(!m_useFilter) return true;

        double spread = GetRealSpread();

        // Determinar limites baseados no símbolo e timeframe
        double maxAcceptable = GetMaxAcceptableSpread();
        double warningThreshold = maxAcceptable * 0.7;

        // Log periódico do spread (não a cada tick!)
        if(m_debugMode) {
            datetime currentTime = TimeCurrent();
            if(currentTime - m_lastLogTime > 300) {  // A cada 5 minutos
                Print("Spread: ", DoubleToString(spread, 1), " pontos (",
                      DoubleToString(spread/10.0, 2), " pips) - Máx: ",
                      DoubleToString(maxAcceptable, 1), " pontos");
                m_lastLogTime = currentTime;
            }
        }

        // Bloquear se spread muito alto
        if(spread > maxAcceptable) {
            if(m_debugMode) {
                Print("BLOQUEIO: Spread ", DoubleToString(spread, 1),
                      " pontos > máximo ", DoubleToString(maxAcceptable, 1));
            }
            return false;
        }

        // Avisar se próximo do limite
        if(spread > warningThreshold) {
            static datetime lastWarning = 0;
            if(TimeCurrent() - lastWarning > 180) {  // A cada 3 minutos
                if(m_debugMode) {
                    Print("AVISO: Spread elevado ", DoubleToString(spread, 1),
                          " pontos (", DoubleToString(spread/10.0, 2), " pips)");
                }
                lastWarning = TimeCurrent();
            }
        }

        return true;
    }

    //+------------------------------------------------------------------+
    //| Obter Spread Máximo Aceitável                                   |
    //+------------------------------------------------------------------+
    double GetMaxAcceptableSpread() {
        string symbol = Symbol();
        ENUM_TIMEFRAMES period = Period();

        // Verificar se é forex major
        bool isForexMajor = (StringFind(symbol, "EUR") >= 0 ||
                            StringFind(symbol, "USD") >= 0 ||
                            StringFind(symbol, "GBP") >= 0 ||
                            StringFind(symbol, "JPY") >= 0);

        if(isForexMajor) {
            // Valores realistas para spread real em pontos
            if(period == PERIOD_M1) {
                return 100.0;  // 10 pips máximo para M1
            } else if(period <= PERIOD_M15) {
                return 150.0;  // 15 pips para M5-M15
            } else {
                return 200.0;  // 20 pips para timeframes maiores
            }
        }

        // Crypto
        if(StringFind(symbol, "BTC") >= 0) {
            return 500.0;  // 50 pips para BTC
        }

        // Outros
        return (double)m_maxSpread;
    }

    //+------------------------------------------------------------------+
    //| Obter Spread Atual Formatado                                    |
    //+------------------------------------------------------------------+
    string GetSpreadString() {
        double spread = GetRealSpread();
        return StringFormat("%.1f pts (%.2f pips)", spread, spread/10.0);
    }
};