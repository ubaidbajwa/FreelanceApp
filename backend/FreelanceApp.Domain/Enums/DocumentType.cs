namespace FreelanceApp.Domain.Enums;

public enum DocumentType
{
    Cnic = 1,           // Pakistan CNIC (front + back, OCR supported)
    Passport = 2,       // International Passport (front only, MRZ OCR supported)
    NationalId = 3,     // Generic national ID card (front + back, varies by country)
    DriversLicense = 4  // Driver's license (front only, varies by country)
}