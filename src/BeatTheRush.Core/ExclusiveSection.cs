namespace BeatTheRush.Core;

/// <summary>A granted direction is intent; an acquired reservation is retained until the tail clears.</summary>
public sealed class ExclusiveSection
{
    public int? OwnerId { get; private set; }
    public string? OwnerRouteId { get; private set; }

    public bool TryAcquire(int trainId, string routeId, string? requestedRoute)
    {
        if (OwnerId == trainId) return true;
        if (OwnerId is not null || requestedRoute != routeId) return false;
        OwnerId = trainId; OwnerRouteId = routeId;
        return true;
    }

    public bool Release(int trainId)
    {
        if (OwnerId != trainId) return false;
        OwnerId = null; OwnerRouteId = null;
        return true;
    }
}


