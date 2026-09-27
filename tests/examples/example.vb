Imports System.Collections.Generic
Imports System.Linq

Public Class Locale
  Public Property Code As String
  Public Property Name As String

  Public Sub New(code As String, name As String)
    Me.Code = code
    Me.Name = name
  End Sub
End Class

Module LocaleResolver
  Function FindLocale(locales As List(Of Locale), code As String) As Locale
    Return locales.FirstOrDefault(Function(l) l.Code.ToLower() = code.ToLower())
  End Function

  Sub Main()
    Dim locales As New List(Of Locale) From {
      New Locale("en", "English"),
      New Locale("pt-BR", "Português")
    }

    Dim match = FindLocale(locales, "pt-BR")
    Console.WriteLine(If(match IsNot Nothing, match.Name, "no match"))
  End Sub
End Module
