import net.sourceforge.vietpad.inputmethod.*;

// Mirrors the actual VietIMEMode.onChar/keyTyped calls, using upstream Java.
public final class VietnameseAudit {
    public static void main(String[] args) throws Exception {
        for (String line : java.nio.file.Files.readAllLines(java.nio.file.Path.of(args[0]))) {
            String[] fields=line.split("\t");
            InputMethod method=fields[0].equals("telex") ? new TelexIM():new VniIM();
            String text="";
            for (char key:fields[1].toCharArray()) {
                String word=text.substring(text.lastIndexOf(' ')+1);
                String converted=word;
                if (!word.isEmpty()) {
                    char accent=method.getAccentMark(key,key,word);
                    if (Character.isDigit(accent)) converted=VietKeyInput.toVietWord(word,accent);
                }
                text=converted.equals(word) ? text+key:text.substring(0,text.length()-word.length())+converted;
            }
            System.out.println(fields[0]+"\t"+fields[1]+"\t"+text);
        }
    }
}
