import SwiftUI
import Charts
import Collections

fileprivate struct BufferStatistic {
    let sampleTime: Date
    let bufferedSeconds: Double
}

struct BufferStatisticsView: View {
    @EnvironmentObject private var model: AppModel

    @State private var statistics = Deque<BufferStatistic>()
    @State private var maxValue = 0.0
    @State private var minValue = 0.0

    var body: some View {
        VStack {
            HStack {
                ZStack {
                    Text("Seconds Buffered")
                        .font(.caption)
                        .rotationEffect(.degrees(-90))
                        .scaledToFill()
                }
                .frame(width: 20)
                GeometryReader { geo in
                    Chart(statistics, id: \.sampleTime) { statistic in
                        AreaMark(
                            x: .value("Sample Time", statistic.sampleTime),
                            y: .value("Seconds Buffered", statistic.bufferedSeconds)
                        )
                        .foregroundStyle(.linearGradient(stops: [
                            .init(color: .green.opacity(0.5), location: 0),
                            .init(color: .clear, location: maxValue / (maxValue - minValue)),
                            .init(color: .red.opacity(0.5), location: 1)
                        ], startPoint: .top, endPoint: .bottom))
                        LineMark(
                            x: .value("Sample Time", statistic.sampleTime),
                            y: .value("Seconds Buffered", statistic.bufferedSeconds)
                        )
                        .foregroundStyle(.linearGradient(stops: [
                            .init(color: .green, location: 0),
                            .init(color: .green, location: maxValue / (maxValue - minValue)),
                            .init(color: .red, location: maxValue / (maxValue - minValue)),
                            .init(color: .red, location: 1)
                        ], startPoint: .top, endPoint: .bottom))
                    }
                    .onReceive(model.refreshTimer) { date in
                        statistics.append(BufferStatistic(sampleTime: date, bufferedSeconds: model.bufferedSeconds))
                        while statistics.count > Int(geo.size.width) {
                            let _ = statistics.popFirst()
                        }
                        let seconds = statistics.map { $0.bufferedSeconds }
                        seconds.max().map { maxValue = max(0, $0) }
                        seconds.min().map { minValue = min(0, $0) }
                    }
                }
            }
            Text("Sample Time")
                .font(.caption)
                .frame(height: 20)
        }
    }
}
