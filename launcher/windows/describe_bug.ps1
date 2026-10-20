param([Parameter(Mandatory=$true)][string]$NotePath)
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$form=New-Object System.Windows.Forms.Form
$form.Text='Describe game bug';$form.Size=New-Object System.Drawing.Size(640,420);$form.StartPosition='CenterScreen'
$text=New-Object System.Windows.Forms.TextBox
$text.Multiline=$true;$text.AcceptsReturn=$true;$text.ScrollBars='Vertical';$text.Location=New-Object System.Drawing.Point(12,12);$text.Size=New-Object System.Drawing.Size(600,310)
$form.Controls.Add($text)
$save=New-Object System.Windows.Forms.Button
$save.Text='Save report';$save.Location=New-Object System.Drawing.Point(490,335);$save.DialogResult='OK';$form.Controls.Add($save)
if($form.ShowDialog() -eq 'OK'){[System.IO.File]::WriteAllText($NotePath,$text.Text,[System.Text.UTF8Encoding]::new($false));exit 0}
exit 1
