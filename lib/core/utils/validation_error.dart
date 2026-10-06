enum ValidationError {
  // GENERAL
  empty,
  tooShort,
  tooLong,

  // EMAIL
  invalidEmail,



  // PHONE
  invalidPhone,
  invalidCountryCode,

  // USERNAME
  invalidUsername,
  usernameTaken,

  // NAME
  invalidName,

  // NUMBER
  notNumber,
  negativeNumber,
  outOfRange,

  // CONFIRMATION
  notMatch,

  // URL
  invalidUrl,
}
