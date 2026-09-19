using Meridian.Messaging.Contracts;

namespace Meridian.Approval.Api.Application;

public interface IEventPublisher
{
    Task PublishAsync<TPayload>(TPayload payload, string correlationId, CancellationToken cancellationToken)
        where TPayload : IMeridianMessage;
}
