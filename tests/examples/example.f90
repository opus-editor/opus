program locale_resolver
  implicit none

  character(len=10), dimension(2) :: codes
  character(len=20), dimension(2) :: names
  character(len=10) :: wanted
  integer :: i
  logical :: found

  codes = [character(len=10) :: "en", "pt-BR"]
  names = [character(len=20) :: "English", "Portugues"]
  wanted = "pt-BR"
  found = .false.

  do i = 1, size(codes)
    if (trim(codes(i)) == trim(wanted)) then
      print *, trim(names(i))
      found = .true.
      exit
    end if
  end do

  if (.not. found) then
    print *, "no match"
  end if
end program locale_resolver
