//+------------------------------------------------------------------+
//|                                            DistanceControl.mqh   |
//|                      Controle de Distância ATR para HedgeLine    |
//|                                  Copyright 2025, HedgeLine EA    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, HedgeLine EA"
#property link      "https://www.hedgeline.com"
#property version   "1.00"

//+------------------------------------------------------------------+
//| Classe para Controle de Distância baseada em ATR               |
//+------------------------------------------------------------------+
class CDistanceControl {
private:
    string m_symbol;
    ENUM_TIMEFRAMES m_timeframe;
    int m_atrPeriod;
    double m_atrMultiplier;
    double m_minDistance;
    double m_maxDistance;
    bool m_debugMode;

    // Cache para otimização
    double m_lastATR;
    datetime m_lastATRTime;
    int m_atrHandle;

    // Controle de log
    datetime m_lastDebugPrint;

public:
    //+------------------------------------------------------------------+
    //| Construtor                                                      |
    //+------------------------------------------------------------------+
    CDistanceControl() {
        m_symbol = Symbol();
        m_timeframe = Period();
        m_atrPeriod = 14;
        m_atrMultiplier = 1.0;
        m_minDistance = 100;
        m_maxDistance = 500;
        m_debugMode = false;
        m_lastATR = 0;
        m_lastATRTime = 0;
        m_atrHandle = INVALID_HANDLE;
        m_lastDebugPrint = 0;
    }

    //+------------------------------------------------------------------+
    //| Destrutor                                                       |
    //+------------------------------------------------------------------+
    ~CDistanceControl() {
        if(m_atrHandle != INVALID_HANDLE) {
            IndicatorRelease(m_atrHandle);
        }
    }

    //+------------------------------------------------------------------+
    //| Inicializar                                                     |
    //+------------------------------------------------------------------+
    bool Init(string symbol, ENUM_TIMEFRAMES timeframe, int atrPeriod,
              double atrMultiplier, double minDistance, double maxDistance,
              bool debugMode) {

        m_symbol = symbol;
        m_timeframe = timeframe;
        m_atrPeriod = atrPeriod;
        m_atrMultiplier = atrMultiplier;
        m_minDistance = minDistance;
        m_maxDistance = maxDistance;
        m_debugMode = debugMode;

        // Criar handle do ATR
        m_atrHandle = iATR(m_symbol, m_timeframe, m_atrPeriod);

        if(m_atrHandle == INVALID_HANDLE) {
            if(m_debugMode) {
                Print("ERRO: Não foi possível criar handle ATR");
            }
            return false;
        }

        return true;
    }

    //+------------------------------------------------------------------+
    //| Obter valor do ATR                                             |
    //+------------------------------------------------------------------+
    double GetATR() {
        if(m_atrHandle == INVALID_HANDLE) {
            return 0;
        }

        // Cache de 1 minuto
        datetime currentTime = TimeCurrent();
        if(m_lastATR > 0 && (currentTime - m_lastATRTime) < 60) {
            return m_lastATR;
        }

        double atrBuffer[];
        ArraySetAsSeries(atrBuffer, true);

        if(CopyBuffer(m_atrHandle, 0, 0, 1, atrBuffer) != 1) {
            if(m_debugMode) {
                Print("ERRO: Não foi possível copiar buffer ATR");
            }
            return m_lastATR;  // Retornar último valor conhecido
        }

        m_lastATR = atrBuffer[0];
        m_lastATRTime = currentTime;

        return m_lastATR;
    }

    //+------------------------------------------------------------------+
    //| Calcular distância dinâmica baseada em ATR                     |
    //+------------------------------------------------------------------+
    double CalculateDynamicDistance() {
        double atr = GetATR();

        if(atr <= 0) {
            // Se ATR não disponível, usar distância mínima
            if(m_debugMode) {
                datetime currentTime = TimeCurrent();
                if(currentTime - m_lastDebugPrint > 60) {  // A cada minuto para debug inicial
                    Print("⚠️ ATR=0, usando distância mínima: ", m_minDistance, " pontos");
                    m_lastDebugPrint = currentTime;
                }
            }
            return m_minDistance;
        }

        // Calcular distância baseada em ATR
        double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
        double atrPoints = atr / point;
        double distance = atrPoints * m_atrMultiplier;

        // Aplicar limites
        if(distance < m_minDistance) {
            distance = m_minDistance;
        } else if(distance > m_maxDistance) {
            distance = m_maxDistance;
        }

        // Debug ocasional
        if(m_debugMode) {
            datetime currentTime = TimeCurrent();
            if(currentTime - m_lastDebugPrint > 300) {  // A cada 5 minutos
                Print("Distância ATR calculada: ", DoubleToString(distance, 1),
                      " pontos (ATR=", DoubleToString(atr, _Digits),
                      ", Mult=", m_atrMultiplier, ")");
                m_lastDebugPrint = currentTime;
            }
        }

        return distance;
    }

    //+------------------------------------------------------------------+
    //| Ajustar distância para M1 (timeframe rápido)                   |
    //+------------------------------------------------------------------+
    double AdjustForM1Scalping() {
        double baseDistance = CalculateDynamicDistance();

        // Para M1, usar distâncias menores
        if(m_timeframe == PERIOD_M1) {
            baseDistance = baseDistance * 0.7;  // Reduzir 30% para M1

            // Limites especiais para M1
            double m1Min = 50;   // Mínimo 5 pips
            double m1Max = 200;  // Máximo 20 pips

            if(baseDistance < m1Min) {
                baseDistance = m1Min;
            } else if(baseDistance > m1Max) {
                baseDistance = m1Max;
            }
        }

        return baseDistance;
    }

    //+------------------------------------------------------------------+
    //| Validar se distância é apropriada para spread atual            |
    //+------------------------------------------------------------------+
    bool ValidateDistanceForSpread(double currentSpread) {
        double distance = CalculateDynamicDistance();

        // Distância deve ser pelo menos 3x o spread
        double minSafeDistance = currentSpread * 3;

        if(distance < minSafeDistance) {
            if(m_debugMode) {
                static datetime lastPrint = 0;
                if(TimeCurrent() - lastPrint > 60) {  // A cada minuto
                    Print("⚠️ Distância muito pequena para spread atual: ",
                          DoubleToString(distance, 1), " pontos < ",
                          DoubleToString(minSafeDistance, 1), " pontos (3x spread)");
                    lastPrint = TimeCurrent();
                }
            }
            return false;
        }

        return true;
    }

    //+------------------------------------------------------------------+
    //| Obter distância para Stop Loss                                 |
    //+------------------------------------------------------------------+
    double GetStopLossDistance() {
        // SL = 1.5x a distância da ordem
        return CalculateDynamicDistance() * 1.5;
    }

    //+------------------------------------------------------------------+
    //| Obter distância para Take Profit                               |
    //+------------------------------------------------------------------+
    double GetTakeProfitDistance() {
        // TP = 2x a distância da ordem
        return CalculateDynamicDistance() * 2.0;
    }

    //+------------------------------------------------------------------+
    //| Atualizar multiplicador ATR                                    |
    //+------------------------------------------------------------------+
    void SetATRMultiplier(double multiplier) {
        if(multiplier > 0 && multiplier <= 5.0) {
            m_atrMultiplier = multiplier;

            if(m_debugMode) {
                Print("Multiplicador ATR atualizado para: ", multiplier);
            }
        }
    }

    //+------------------------------------------------------------------+
    //| Obter informações de debug                                     |
    //+------------------------------------------------------------------+
    string GetDebugInfo() {
        double atr = GetATR();
        double distance = CalculateDynamicDistance();

        return StringFormat("ATR=%.5f, Dist=%.1f pts (Min=%.0f, Max=%.0f)",
                          atr, distance, m_minDistance, m_maxDistance);
    }

    //+------------------------------------------------------------------+
    //| Verificar volatilidade do mercado                              |
    //+------------------------------------------------------------------+
    string GetMarketVolatility() {
        double atr = GetATR();
        double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
        double atrPips = (atr / point) / 10.0;  // Converter para pips

        // Classificar volatilidade baseada em pips
        if(atrPips < 5) {
            return "Baixa";
        } else if(atrPips < 10) {
            return "Normal";
        } else if(atrPips < 20) {
            return "Alta";
        } else {
            return "Muito Alta";
        }
    }

    //+------------------------------------------------------------------+
    //| Resetar cache                                                  |
    //+------------------------------------------------------------------+
    void ResetCache() {
        m_lastATR = 0;
        m_lastATRTime = 0;
    }
};