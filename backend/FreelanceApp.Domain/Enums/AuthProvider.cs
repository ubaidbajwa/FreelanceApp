namespace FreelanceApp.Domain.Enums;

// User kis darwaze se aaya — normal email ya social
public enum AuthProvider
{
    Local = 0,      // email + password wala purana tarika
    Google = 1,
    Microsoft = 2,
    Apple = 3
}
