#!/usr/bin/env python

import unittest
from selenium import webdriver
from selenium.webdriver.common.keys import Keys
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.common.by import By
from selenium.webdriver.support import expected_conditions
from selenium.webdriver.support.ui import WebDriverWait
from time import sleep
import json
import sys
import os

def die(msg):
    print "Error: %s" % msg
    exit(1)

def getDCOSToken():
    username = os.environ.get('DCOS_OAUTH_USER')
    password = os.environ.get('DCOS_OAUTH_PASSWORD')
    if username == None or password == None:
        die("missing credentials")
    hostname = os.environ.get('DCOS_HOSTNAME')
    if hostname == None:
        die("missing URL")

    chrome_options = Options()
    chrome_options.add_argument("--headless")

    browser = webdriver.Chrome("chromedriver", chrome_options=chrome_options)
    browser.implicitly_wait(10)
    browser.set_page_load_timeout(10)
    browser.get("http://"+ hostname + "/login?redirect_uri=urn:ietf:wg:oauth:2.0:oob")
    
    try:
        windowslive = WebDriverWait(browser, 10).until(
            expected_conditions.presence_of_element_located((By.XPATH, '//button[@id="windowslive"]'))
        )
        windowslive = browser.find_element_by_xpath('//button[@id="windowslive"]')
        windowslive.click()
    except:
        browser.quit()
        raise

    dcoswindow = browser.window_handles[0]
    loginwindow = browser.window_handles[1]
    browser.switch_to_window(loginwindow)
    
    try:
        emailtextbox = WebDriverWait(browser, 10).until(
            expected_conditions.presence_of_element_located((By.XPATH, '//input[@type="email"]'))
        )
        emailtextbox = browser.find_element_by_xpath('//input[@type="email"]')
        emailtextbox.click()
        emailtextbox.send_keys(username)
        emailtextbox.send_keys(Keys.RETURN)
    except:
        browser.quit()
        raise

    sleep(1)
    try:
        passwordtextbox = WebDriverWait(browser, 10).until(
            expected_conditions.presence_of_element_located((By.XPATH, '//input[@type="password"]'))
        )
        passwordtextbox = browser.find_element_by_xpath('//input[@type="password"]')
        passwordtextbox.send_keys(password)
        passwordtextbox.send_keys(Keys.RETURN)
    except:
        browser.quit()
        raise
        
    try:
        accept_access_box = WebDriverWait(browser, 1).until(
            expected_conditions.presence_of_element_located((By.XPATH, '//input[@type="submit"][@value="Yes"]'))
        )
        accept_access_box = browser.find_element_by_xpath('//input[@type="submit"][@value="Yes"]')
        accept_access_box.click()
    except:
        pass

    browser.switch_to_window(dcoswindow)

    try:
        token_box = WebDriverWait(browser, 10).until(
            expected_conditions.presence_of_element_located((By.XPATH, '//div[@class="snippet-wrapper"]/pre'))
        )
        token_box = browser.find_element_by_xpath('//div[@class="snippet-wrapper"]/pre')
        print(token_box.text)
    except:
        browser.quit()
        raise

    browser.quit()

   
if __name__ == '__main__':
    getDCOSToken()
