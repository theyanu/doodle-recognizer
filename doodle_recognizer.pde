import gab.opencv.*;
import processing.video.*;
import java.awt.*;
import http.requests.*; 
import java.net.*;
import java.io.*;
import java.util.Collections;
import java.util.Comparator;

Capture video;
OpenCV opencv;
OpenCV opencv_bg;

int x,y,l;
FloatDict score;
ArrayList<Contour> contours;

void setup() {
  size(1280, 768);
  video = new Capture(this, 1280, 768);
  opencv = new OpenCV(this, 1280, 768);
  opencv_bg = new OpenCV(this, 1280, 768);
  video.start();
  
  l = width > height ? height/2 : width/2;
  x = width/2 - l/2;
  y = height/2 - l/2;
  
  score = new FloatDict();
}

void draw() {
  //background area
  opencv_bg.loadImage(video);
  opencv_bg.gray();
  opencv_bg.blur(70);
  image(opencv_bg.getSnapshot(), 0,0);
  
  //shape-recognition area
  stroke(90, 90, 90);
  fill(30,30,30);
  rect(x,y,l,l);
  
  opencv.loadImage(video);
  opencv.gray();
  opencv.setROI(x, y, l,l);
  opencv.threshold(70);
  
  //text info area
  fill(43, 255, 145);
  stroke(43, 255, 145);
  rect(x, y-40, l, 40);
  
  textSize(15);
  fill(30,30,30);
  text("Place drawn shape in this area & press any key.", this.x+12, this.y-14);
  
  //text score area
  if (this.score.size() > 0) {
    stroke(90, 90, 90);
    fill(30,30,30);
    rect(x+l+24,y,300,l);
    
    fill(56, 155, 255);
    stroke(56, 155, 255);
    rect(x+l+24, y-40, 300, 40);
    
    textSize(15);
    fill(30,30,30);
    text("I guess your drawing is...", this.x+l+36, this.y-14);
  
   
    for(int i = 0; i < 10; i++) {
      if (i == 0) fill(43, 255, 145);
      else fill(255,255,255);
      text((i+1) + ". " + this.score.keyArray()[i], x+l+36, y+24+30*i);
    }
  }

  //contours in shape-recognition area
  noFill();
  stroke(43, 255, 145);
  strokeWeight(1);  
  
  contours = opencv.findContours();
  Collections.sort(contours, new Comparator<Contour>() {
      @Override
      public int compare(Contour a, Contour b) {
          return  (int) (b.area() - a.area());
      }
  });
  
  for (int i = 1; i < contours.size(); i++) {
    if (contours.get(i-1).area() - contours.get(i).area() < 20000) {
      contours.remove(i);
    }
  }
  if (contours.size() > 0 && contours.get(0).area() > 140000) contours.remove(0);
  for (Contour contour : contours) {
    beginShape();
    for (PVector point : contour.getPoints()) vertex(x + point.x, y + point.y);
    endShape();
  }  
}

void captureEvent(Capture c) {
  c.read();
}

//reacts to any key press
void keyPressed() { 
  JSONArray ink = new JSONArray();
  
  //fill all contures to array "ink".
  for (int j = 0;  j < contours.size(); j++) {
    Contour contour = contours.get(j);
    
    ArrayList<PVector> points = contour.getPoints();
    
    JSONArray tempX = new JSONArray();
    JSONArray tempY = new JSONArray();
    
    for (int i = 0; i < points.size() - 5; i++) {
      PVector p = points.get(i);
      tempX.append(points.get(i).x);
      tempY.append(points.get(i).y);
    }
  
    JSONArray line = new JSONArray();
    line.append(tempX);
    line.append(tempY);
    ink.append(line);
    
  }
  callAPI(ink);
}

private void callAPI(JSONArray ink) {
 JSONObject json = buildJSON(ink);
 sendRequest(json.toString());
}

private JSONObject buildJSON(JSONArray ink){
 JSONObject json = new JSONObject();
 json.setString("options","enable_pre_space");
 
 JSONObject requests = new JSONObject();  
 requests.setJSONArray("ink", ink);
 requests.setString("language","quickdraw");
 
 JSONObject writingGuide = new JSONObject();  
 writingGuide.setInt("writing_area_width", l);
 writingGuide.setInt("writing_area_height", l);  
 requests.setJSONObject("writing_guide", writingGuide);

 json.setJSONArray("requests", new JSONArray().append(requests));
 return json;
}

//sends request to Google Input-Tools API (Used in https://quickdraw.withgoogle.com/)
private void sendRequest(String jsonContent) {
  URL url;
  
  try {
   url = new URL("https://inputtools.google.com/request?ime=handwriting&app=quickdraw&dbg=1&cs=1&oe=UTF-8");
  } catch(MalformedURLException e) { 
    return; 
  }
  
  HttpURLConnection conn = null;
  
  try {
    conn = (HttpURLConnection) url.openConnection();
    try {
      conn.setRequestMethod("POST"); 
      conn.setDoOutput(true);
      conn.setDoInput(true);
      conn.setUseCaches(false);
      conn.setAllowUserInteraction(false);
      conn.setRequestProperty("Content-Type","application/json");
    } 
    catch (ProtocolException e) {}
    
    OutputStream out = conn.getOutputStream();
    try {
      OutputStreamWriter wr = new OutputStreamWriter(out);
      wr.write(jsonContent);
      wr.flush();
      wr.close();
    }
    catch (IOException e) {}
    
    finally {
      if (out != null)
        out.close();
    }
    
    InputStream in = conn.getInputStream();
    
    //reading line that contains "debug_info" information, as there the score values can be found.
    try {
      BufferedReader rd  = new BufferedReader(new InputStreamReader(in));
      String line;
      while ((line = rd.readLine()) != null) {
        if (line.contains("debug_info")) {
          this.score = getScore(line);
          break;
        }
      }
      
      rd.close();
    }
    catch (IOException e) {}
    finally { 
      if (in != null)
        in.close();
    }
  }
  catch (IOException e) {} 
  finally {
    if (conn != null)
      conn.disconnect();
  }
}

//extracts score information from string
private FloatDict getScore(String value) {
    FloatDict dict = new FloatDict();
    String[] pairs = split(value, "[\\\"");
    
    for(String s : pairs) {
      String[] items = split(s, "\\\",");
      if (items.length != 2) continue;
      dict.add(items[0], Float.parseFloat(split(items[1], "]")[0]));
    }
   
    dict.sortValues();
    return dict;
}