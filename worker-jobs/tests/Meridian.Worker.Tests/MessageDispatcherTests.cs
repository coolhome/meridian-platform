using Meridian.Messaging.Contracts;
using Meridian.Messaging.Contracts.Events;
using Meridian.Worker.Messaging;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace Meridian.Worker.Tests;

public sealed class MessageDispatcherTests
{
    private sealed class RecordingHandler(bool fail = false) : IMessageHandler<ApprovalRequested>
    {
        public List<MessageEnvelope<ApprovalRequested>> Seen { get; } = [];

        public Task HandleAsync(MessageEnvelope<ApprovalRequested> envelope, CancellationToken cancellationToken)
        {
            if (fail)
            {
                throw new InvalidOperationException("boom");
            }

            Seen.Add(envelope);
            return Task.CompletedTask;
        }
    }

    private static string Requested() => MessageSerializer.Serialize(MessageEnvelope.Create(
        new ApprovalRequested(Guid.NewGuid(), "Laptop", "alice", ["bob"], DateTimeOffset.UtcNow, null), "test"));

    private static MessageDispatcher<ApprovalRequested> Dispatcher(RecordingHandler handler, int max = 5)
        => new(handler, max, NullLogger<MessageDispatcher<ApprovalRequested>>.Instance);

    [Fact]
    public async Task Valid_message_is_handled()
    {
        var handler = new RecordingHandler();
        var result = await Dispatcher(handler).DispatchAsync(new IncomingMessage("1", Requested(), 1, DateTimeOffset.UtcNow), CancellationToken.None);
        Assert.Equal(DispatchOutcome.Handled, result.Outcome);
        Assert.Single(handler.Seen);
    }

    [Fact]
    public async Task Too_many_dequeues_and_wrong_type_are_poisoned()
    {
        var handler = new RecordingHandler();
        var d = Dispatcher(handler, max: 3);

        Assert.Equal(DispatchOutcome.Poison, (await d.DispatchAsync(new IncomingMessage("1", Requested(), 4, null), CancellationToken.None)).Outcome);

        var decided = MessageSerializer.Serialize(MessageEnvelope.Create(new ApprovalDecided(Guid.NewGuid(), ApprovalDecision.Approved, "bob", null, DateTimeOffset.UtcNow), "test"));
        Assert.Equal(DispatchOutcome.Poison, (await d.DispatchAsync(new IncomingMessage("2", decided, 1, null), CancellationToken.None)).Outcome);

        Assert.Equal(DispatchOutcome.Poison, (await d.DispatchAsync(new IncomingMessage("3", "not json", 1, null), CancellationToken.None)).Outcome);
        Assert.Empty(handler.Seen);
    }

    [Fact]
    public async Task Handler_failure_requests_retry()
    {
        var result = await Dispatcher(new RecordingHandler(fail: true)).DispatchAsync(new IncomingMessage("1", Requested(), 2, null), CancellationToken.None);
        Assert.Equal(DispatchOutcome.Retry, result.Outcome);
        Assert.Equal("boom", result.Reason);
    }
}
