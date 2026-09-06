namespace FreelanceApp.Domain.Enums;

// Sirf Text M1 mein use hota hai. Baaki values abhi define kar diye taake baad ke
// slices additive rahein — naya enum member add karne pe migration churn na ho.
public enum MessageType
{
    Text   = 0,
    Image  = 1,
    File   = 2,
    Voice  = 3,
    System = 4,  // Inline activity marker (pin/unpin). Body is always empty; client renders from SystemEventType.
    Video  = 5   // Media message (M-M4). 4 is TAKEN by System — reusing it would silently re-type every existing
                 // pin/unpin row. Image = 1 was reserved in M1; M-M4 makes Image and Video real.
}
