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
    private var maxValue: Double { max(statistics.map({ $0.bufferedSeconds }).max()!, 0) }
    private var minValue: Double { min(statistics.map({ $0.bufferedSeconds }).min()!, 0) }

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
                    .onReceive(model.guiRefreshTimer) { date in
                        withAnimation {
                            statistics.append(BufferStatistic(sampleTime: date, bufferedSeconds: model.bufferedSeconds))
                            while statistics.count > Int(geo.size.width) {
                                let _ = statistics.popFirst()
                            }
                        }
                    }
                }
            }
            Text("Sample Time")
                .font(.caption)
                .frame(height: 20)
        }
    }
}
