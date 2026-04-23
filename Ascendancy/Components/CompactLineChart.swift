import SwiftUI
import Charts

// MARK: - Compact Line Chart (sparkline style)

struct CompactLineChart: View {
    let dataPoints: [ActiveLevelDataPoint]
    var lineColor: Color = .white
    var showGradient: Bool = true
    var showCurrentDot: Bool = true
    var height: CGFloat = 60

    // Pre-computed max level to avoid recalculation on every render
    private let maxLevel: Double

    init(dataPoints: [ActiveLevelDataPoint], lineColor: Color = .white, showGradient: Bool = true, showCurrentDot: Bool = true, height: CGFloat = 60) {
        self.dataPoints = dataPoints
        self.lineColor = lineColor
        self.showGradient = showGradient
        self.showCurrentDot = showCurrentDot
        self.height = height
        self.maxLevel = dataPoints.map(\.level).max() ?? 1
    }

    var body: some View {
        if dataPoints.isEmpty {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.04))
                .frame(height: height)
                .overlay(
                    Text("No data")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.2))
                )
        } else {
            Chart {
                if showGradient {
                    ForEach(dataPoints) { point in
                        AreaMark(
                            x: .value("Time", point.date),
                            y: .value("Level", point.level)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [lineColor.opacity(0.3), lineColor.opacity(0.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)
                    }
                }

                ForEach(dataPoints) { point in
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Level", point.level)
                    )
                    .foregroundStyle(lineColor)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .interpolationMethod(.catmullRom)
                }

                if showCurrentDot, let last = dataPoints.last {
                    PointMark(
                        x: .value("Time", last.date),
                        y: .value("Level", last.level)
                    )
                    .foregroundStyle(lineColor)
                    .symbolSize(30)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: 0...(maxLevel * 1.2))
            .frame(height: height)
        }
    }
}

// MARK: - Health Metric Chart

struct HealthMetricChart: View {
    let dataPoints: [HealthMetricPoint]
    let title: String
    let unit: String
    var lineColor: Color = .blue
    var days: Int = 30
    
    var latestValue: Double? { dataPoints.last?.value }
    var minValue: Double { dataPoints.map(\.value).min() ?? 0 }
    var maxValue: Double { dataPoints.map(\.value).max() ?? 1 }
    
    var yDomain: ClosedRange<Double> {
        let range = maxValue - minValue
        let padding = range > 0 ? range * 0.1 : max(maxValue * 0.1, 1)
        let lower = max(0, minValue - padding)
        let upper = maxValue + padding
        return lower...upper
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                if let latest = latestValue {
                    Text(latest.formatted(.number.precision(.fractionLength(0...1))))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(catalogKey: unit)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .offset(y: -1)
                }
                Spacer()
                Text(String(format: String(localized: "%lldd"), days))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.3))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Capsule())
            }
            
            if dataPoints.isEmpty {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.04))
                    .frame(height: 70)
                    .overlay(Text("No data").font(.system(size: 12)).foregroundStyle(.white.opacity(0.2)))
            } else {
                Chart {
                    ForEach(dataPoints) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value(title, point.value)
                        )
                        .foregroundStyle(lineColor)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.catmullRom)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: max(1, days / 5))) { value in
                        if let date = value.as(Date.self) {
                            AxisValueLabel {
                                Text(date, format: .dateTime.month(.abbreviated).day())
                                    .font(.system(size: 9))
                                    .foregroundStyle(.white.opacity(0.3))
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3, dash: [3]))
                            .foregroundStyle(Color.white.opacity(0.08))
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(v.formatted(.number.precision(.fractionLength(0))))
                                    .font(.system(size: 9))
                                    .foregroundStyle(.white.opacity(0.3))
                            }
                        }
                    }
                }
                .chartYScale(domain: yDomain)
                .frame(height: 100)
            }
        }
    }
}
