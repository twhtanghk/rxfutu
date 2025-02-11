_ = require 'lodash'
Futu = require '../index'
moment = require 'moment'
{ bufferCount, map } = require 'rxjs'

hilbertTrendVsRangeIndicator = (candles$, lpPeriod = 20, filtTop = 48) ->
  candles$.pipe(
    # Buffer to store the last few candles for calculation
    bufferCount(lpPeriod, 1)  # Adjust buffer size as needed
    
    # Calculate the Hilbert Transform components
    map (candles) ->
      prices = candles.map (candle) -> candle.close
      inPhase = []
      quadrature = []
      
      # Apply low-pass filter and Hilbert Transform
      for i in [1...prices.length]
        delta = prices[i] - prices[i-1]
        sum = prices[i] + prices[i-1]
        
        # Low-pass filter to smooth the data
        if i >= lpPeriod
          smoothedDelta = (delta + (inPhase[i-2] ? 0) * (lpPeriod - 1)) / lpPeriod
          smoothedSum = (sum + (quadrature[i-2] ? 0) * (lpPeriod - 1)) / lpPeriod
        else
          smoothedDelta = delta
          smoothedSum = sum
        
        # Apply frequency filtering (filtTop)
        inPhase.push(smoothedDelta * filtTop)
        quadrature.push(smoothedSum * filtTop)
      
      { inPhase, quadrature, candles }
    
    # Calculate the Trend and Range
    map ({ inPhase, quadrature, candles }) ->
      trend = inPhase.reduce(((sum, val) -> sum + val), 0) / inPhase.length
      range = quadrature.reduce(((sum, val) -> sum + val), 0) / quadrature.length
      { trend, range, candles }
    
    # Normalize the indicator
    map ({ trend, range, candles }) ->
      normalizedTrend = trend / range
      normalizedRange = 1 - normalizedTrend
      
      trend: normalizedTrend
      range: normalizedRange
      timestamp: candles[candles.length - 1].timestamp
  )

do ->
  futu = await new Futu()
  kl = (await futu
    .dataKL
      market: 'hk'
      code: '01211'
      start: moment().subtract month: 3
      freq: '1d'
    )
    .pipe map (x) ->
      _.extend x, timestamp: new Date x.timestamp * 1000
    
  hilbertTrendVsRangeIndicator kl
    .subscribe console.log
