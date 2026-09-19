using System.Diagnostics.Metrics;
using Meridian.Messaging.Contracts;

namespace Meridian.Worker.Messaging;

/// <summary>Custom metrics and structured events used by observability/kql and the platform workbook.</summary>
public sealed class WorkerTelemetry : IDisposable
{
    private readonly ILogger<WorkerTelemetry> _logger;
    private readonly Meter _meter;
    private readonly Histogram<double> _lagSeconds;
    private readonly Counter<long> _poisoned;
    private readonly Dictionary<string, long> _lengths = new(StringComparer.Ordinal);
    private readonly Lock _gate = new();

    public WorkerTelemetry(ILogger<WorkerTelemetry> logger, IMeterFactory meterFactory)
    {
        _logger = logger;
        _meter = meterFactory.Create("Meridian.Worker");
        _lagSeconds = _meter.CreateHistogram<double>("meridian.queue.lag_seconds", unit: "s", description: "Seconds between enqueue and successful handling");
        _poisoned = _meter.CreateCounter<long>("meridian.queue.poisoned", description: "Messages moved to a poison queue");
        _meter.CreateObservableGauge("meridian.queue.approximate_length", ObserveLengths, description: "Approximate queue length at last receive");
    }

    public void RecordQueueLength(string queue, long length)
    {
        lock (_gate)
        {
            _lengths[queue] = length;
        }
    }

    public void RecordHandled(string queue, MessageHeader? header, long dequeueCount, DateTimeOffset? insertedOn)
    {
        var lag = insertedOn is { } t ? (DateTimeOffset.UtcNow - t).TotalSeconds : double.NaN;
        if (!double.IsNaN(lag))
        {
            _lagSeconds.Record(lag, new KeyValuePair<string, object?>("queue", queue));
        }

        _logger.LogInformation("MessageHandled {MessageType} {MessageId} queue={Queue} dequeueCount={DequeueCount} lagSeconds={LagSeconds:F1}",
            header?.MessageType, header?.MessageId, queue, dequeueCount, lag);
    }

    public void RecordPoisoned(string queue, string reason)
    {
        _poisoned.Add(1, new KeyValuePair<string, object?>("queue", queue));
        _logger.LogWarning("MessagePoisoned queue={Queue} reason={Reason}", queue, reason);
    }

    private IEnumerable<Measurement<long>> ObserveLengths()
    {
        lock (_gate)
        {
            return _lengths.Select(kv => new Measurement<long>(kv.Value, new KeyValuePair<string, object?>("queue", kv.Key))).ToArray();
        }
    }

    public void Dispose() => _meter.Dispose();
}
